#!/bin/bash

######################################################################################
#
# Author: Ryan Huang <ryanhuang@cs.ucsd.edu>
#
# Functionality: Given two LaTeX paper projects, generate a pdf file with differences
#                highlighted. This makes it easier for people to give feedbacks 
#                on changed items in the papers.
#
######################################################################################

USAGE="Usage: `basename $0` [-h] [-o OUTPUT] OLDDIR NEWDIR ENTRY \n\n \
  Example: ./genlatexdiff.sh -o diff.pdf paper-old paper-new paper.tex 2>&1 | tee diff.out\n\n
" 

OUTPUT=
has_output=0
modified=()
bakext="org"

function die()
{
  echo "Error: $1" >&2
  cleanup
  exit 1
}

function standarize()
{
  for f in *.tex
  do
    grep -e "\([^\\\]*\)\\\input *\([a-zA-Z][a-zA-Z]*\)\(.*\)" $f > /dev/null
    if [ $? -eq 0 ]; then
      modified+=($f.$bakext)
      sed -i.$bakext -e "s:\([^\\\]*\)\\\input *\([a-zA-Z][a-zA-Z]*\)\(.*\):\1\\\input{\2}\3:" \
          -e "s:\%\\\input *\([a-zA-Z][a-zA-Z]*\)\(.*\)::" -e "s:\%\\\input *{ *\([a-zA-Z][a-zA-Z]*\) *}\(.*\)::" $f
    fi
  done
}

function isdir()
{
  if [ ! -d $1 ]; then
    die "'$1' is not a directory."
  fi
}

function isfile()
{
  if [ ! -f $1 ]; then
    die "'$1' does not exist."
  fi
}

function searchmake()
{
  if [ -f GNUmakefile ]; then
    echo GNUmakefile
  fi
  if [ -f makefile ]; then
    echo makefile
  fi
  if [ -f Makefile ]; then
    echo Makefile
  fi
}

function revert()
{
  if [ -f $1 ]; then
    f_ext=${1##*.}
    if [ $f_ext = $bakext ]; then
      f_base=${1%.*}
      echo "reverting $1..."
      mv -f $1 $f_base
    fi
  fi
}

function cleanup()
{
  for f in ${modified[@]}
  do
    revert $f
  done
  if [ -f $mkfile.$bakext ]; then
    revert $mkfile.$bakext
  fi
  find -maxdepth 1 -name "$tmpbase.*" ! -name $tmpbase.pdf -exec rm {} \;
}

while getopts ho: OPT; do
  case "$OPT" in 
    h)
      echo -e $USAGE
      exit 0
      ;;
    o)
      OUTPUT=$OPTARG
      has_output=1
      ;;
    ?)
      echo -e $USAGE >&2
      exit 1
      ;;
  esac
done

shift `expr $OPTIND - 1`
if [ $# -ne 3 ]; then
  echo -e $USAGE
  exit 1
fi
if [ -z `which latexdiff` ]; then
  die "latexdiff is not available in the system. Please install it."
fi
old=$1
new=$2
entry=$3
isdir $old
isdir $new
isfile $old/$entry
isfile $new/$entry
base=`pwd`
cd $old
old=`pwd`
echo "patching sources in $old..."
standarize
cd $base
cd $new
new=`pwd`
echo "patching sources in $new..."
standarize
echo "making temporary file..."
tmpbase=$(mktemp -t diffs.XXXXXX --tmpdir=. -u)
tmpbase=$(basename $tmpbase) # remove ./
if [ -z $tmpbase ]; then
  die "cannot compute temporary file name."
fi
tmptex=$tmpbase.tex
echo "temporary file created: $tmptex."
if [ -z $OUTPUT ]; then
  OUTPUT=$tmpbase.pdf
fi
echo "calculating diff between $old and $new..."
latexdiff --flatten $old/$entry $entry > $tmptex
if [ $? -ne 0 ]; then
  die "failed to generate latex diff file"
  rm $tmptex
fi
echo "searching for makefile..."
mkfile=`searchmake`
if [ -z $mkfile ]; then
  echo "makefile not found."
  echo "compiling $tmptex in traditional way..."
  latex $tmptex  & latex $tmptex & dvips -P cmz $tmpbase.dvi \
    -o $tmpbase.ps -t letter & ps2pdf $tmpbase.ps $OUTPUT
  if [ $? -ne 0 ]; then
    die "compilation failed."
    rm $tmpbase.*
  fi
  echo "compilation succeed"
  echo "cleaning up temporary file..."
  rm $tmpbase.*
  echo "You can view $OUTPUT in $new now."
else
  echo "patching makefile..."
  entry_base=${entry%%.*}
  exts="tex ps pdf dvi out"
  repstr="-e s:\b$entry_base\b:$tmpbase:"
  for e in $exts
  do
    repstr="$repstr -e s:\b$entry_base\.$e\b:$tmpbase\.$e:" 
  done
  echo "sed -i.$bakext $repstr $mkfile"
  sed -i.$bakext  $repstr $mkfile
  if [ $? -ne 0 ]; then
    die "patching makefile failed."
  fi
  echo "invoking make..."
  make
  if [ $? -ne 0 ]; then
    die "make failed."
    rm $tmpbase.*
  fi
  if [ ! -z OUTPUT ]; then
    mv $tmpbase.pdf $OUTPUT
  fi
  echo "make succeed."
  cleanup
  echo "You can view $OUTPUT in $new now!"
fi
