#!/usr/bin/env bash -e

abspath() {
  # $1 : relative filename
  echo "$PWD/$@"
}

function error(){
    echo $@ 1>&2
    exit 1
}

function get_name(){
    title=$(grep -Eo '<title>(.+)</title>' "$path" | perl -pe 's/<.+?>//g')
    name=$(echo "$title" | sed -e 's%\(.*\) /.*%\1%')

    echo "$name"
}

function add_to_index(){
    path="$1"
    page_name=$(get_name "$path")

    echo "INSERT OR IGNORE INTO searchIndex(name, type, path)
    VALUES('$page_name', 'Guide', '$path');
    " | sqlite3 "$DB"
    
    for link in $(grep -Eo 'href="#[^"]+">.+?<' "$path" || true); do
        name=$(echo "$link" | perl -p -e 's/.*>(.+?)</\1/')
        name=$(echo "$name" | sed -e "s/'/''/g")
        anchor=$(echo "$link" | perl -p -e 's/.+?"(#.+?)".*/\1/')

        echo "INSERT OR IGNORE INTO searchIndex(name, type, path)
        VALUES('$name', 'Section', '$path$anchor');
        " | sqlite3 "$DB"
    done
}

IFS=$'\n'
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONTENTS_DIR="$(abspath vimscript.docset/Contents)"
DB="$CONTENTS_DIR/Resources/docSet.dsidx"

cd "$BASE_DIR"

BASE_DIR=$PWD

echo 'Fetching (and updating) learnvimscriptthehardway'
if [ -d learnvimscriptthehardway ]; then
    cd learnvimscriptthehardway
    git pull
    cd ..
else
    git clone https://github.com/sjl/learnvimscriptthehardway
fi

echo 'Fetching (and updating) bookmarkdown'
if [ -d bookmarkdown ]; then
    cd bookmarkdown
    git pull
    cd ..
else
    git clone https://github.com/sjl/bookmarkdown.git
fi

python -c 'import baker' || error 'Please install baker, You can try:' \
    '"pip install baker"'

python -c 'import markdown' || error 'Please install markdown, You can try:' \
    '"pip install markdown"'

python -c 'import pyquery' || error 'Please install pyquery, You can try:' \
    '"pip install pyquery"'

cd learnvimscriptthehardway
echo 'Building learnvimscriptthehardway'
. ./build.sh

cd "$BASE_DIR"

if [ -d "$CONTENTS_DIR/Resources/Documents" ]; then
    rm -rf "CONTENTS_DIR/Resources/Documents"
fi

if [ -f "$DB" ]; then
    rm "$DB"
fi

mkdir -p "$CONTENTS_DIR/Resources/"
rsync -a learnvimscriptthehardway/build/html/ \
    "$CONTENTS_DIR/Resources/Documents/"

echo "
CREATE TABLE searchIndex(
    id INTEGER PRIMARY KEY,
    name TEXT,
    type TEXT,
    path TEXT
);
CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);
" | sqlite3 "$DB"

echo "Building search index"
cd "$CONTENTS_DIR/Resources/Documents"
for path in *.html; do
    echo "$path"
    perl -pi -e 's%(href|src)="/%$1="%g' "$path"
    add_to_index "$path"
done

for path in */*.html; do
    echo "$path"
    perl -pi -e 's%(href|src)="/%$1="../%g' "$path"
    add_to_index "$path"
done

cd "$BASE_DIR"
echo "Packaging"
tar --exclude='.DS_Store' -cvzf vimscript.tgz vimscript.docset

