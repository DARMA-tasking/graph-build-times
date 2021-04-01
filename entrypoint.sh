#!/bin/bash

# set -euo pipefail
set -x


cd "$GITHUB_WORKSPACE"
ls

if [ -z "$GITHUB_ACTOR" ]; then
    echo "GITHUB_ACTOR environment variable is not set"
    exit 1
fi

if [ -z "$GITHUB_REPOSITORY" ]; then
    echo "GITHUB_REPOSITORY environment variable is not set"
    exit 1
fi

if [ -z "${INPUT_GITHUB_PERSONAL_TOKEN}" ]; then
    echo "github-personal-token environment variable is not set"
    exit 1
fi

# include-what-you-use
wget https://include-what-you-use.org/downloads/include-what-you-use-0.14.src.tar.gz
tar xzf include-what-you-use-0.14.src.tar.gz --one-top-level=include-what-you-use --strip-components 1
cd include-what-you-use
mkdir build && cd build
cmake .. && make && make install
cd "$GITHUB_WORKSPACE"

# ClangBuildAnalyzer
git clone https://github.com/aras-p/ClangBuildAnalyzer
cd ClangBuildAnalyzer
mkdir build && cd build

cmake .. && make
chmod +x ClangBuildAnalyzer
ClangBuildTool="$GITHUB_WORKSPACE/ClangBuildAnalyzer/build/ClangBuildAnalyzer"
cd "$GITHUB_WORKSPACE"


VT_BUILD_FOLDER="$GITHUB_WORKSPACE/build/vt"

# BUILD VT
mkdir -p build/vt
$ClangBuildTool --start $VT_BUILD_FOLDER
/build_vt.sh $GITHUB_WORKSPACE $GITHUB_WORKSPACE/build "-ftime-trace" OFF
$ClangBuildTool --stop $VT_BUILD_FOLDER vt-build
$ClangBuildTool --analyze vt-build > build_result.txt

iwyu_tool.py -p $VT_BUILD_FOLDER > include-what-you-use.txt

# Build VT in a standard way to measure build time
rm -rf $GITHUB_WORKSPACE/build
/build_vt.sh $GITHUB_WORKSPACE $GITHUB_WORKSPACE/build

# GENERATE BUILD TIME GRAPH
tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
(
    WIKI_URL="https://${INPUT_GITHUB_PERSONAL_TOKEN}@github.com/$GITHUB_REPOSITORY.wiki.git"

    cd "$tmp_dir" || exit 1
    git init
    git config user.name "$GITHUB_ACTOR"
    git config user.email "$GITHUB_ACTOR@users.noreply.github.com"
    git pull "$WIKI_URL"

    # Generate graph
    cat $VT_BUILD_FOLDER/build_time.txt
    build_time=$(grep -oP 'real\s+\K\d+m\d+\.\d+s' $VT_BUILD_FOLDER/build_time.txt)
    python3 /generate_graph.py -t $build_time -r $INPUT_RUN_NUMBER

    cp "$GITHUB_WORKSPACE/build_result.txt" .
    cp "$GITHUB_WORKSPACE/include-what-you-use.txt" .

    git add .
    git commit -m "$INPUT_COMMIT_MESSAGE"
    git push --set-upstream "$WIKI_URL" master
) || exit 1

rm -rf "$tmp_dir"

exit 0
