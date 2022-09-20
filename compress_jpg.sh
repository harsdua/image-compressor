#!/bin/bash
#By: Harsh Dua
#Matricule: 509461

#Compress_jpg is a script that will compress images by imagemagick

# Formatted usage messages
SHORT_USAGE="\e[1mUSAGE\e[0m
    \e[1m${0}\e[0m [\e[1m-c\e[0m] [\e[1m-r\e[0m] [\e[1m-e\e[0m \e[4mextension\e[0m] \e[4mresolution\e[0m [\e[4mfilename_or_directory\e[0m]
or
    \e[1m${0} --help\e[0m
for detailed help."


USAGE="$SHORT_USAGE

The order of the options does not matter. However, if \e[4mfilename_or_directory\e[0m is given and is a number, it must appear after \e[4mresolution\e[0m.

  \e[1m-c\e[0m, \e[1m--strip\e[0m
    Compress more by removing metadata from the file.

  \e[1m-r\e[0m, \e[1m--recursive\e[0m
    If \e[4mfilename_or_directory\e[0m is a directory, recursively compress JPEG in subdirectories.
    Has no effect if \e[4mfilename_or_directory\e[0m is a regular file.
    This option has the same effect when file and directories are given on stdin.

  \e[1m-e\e[0m \e[4mextension\e[0m, \e[1m--ext\e[0m \e[4mextension\e[0m
    Change the extension of processed files to \e[4mextension\e[0m, even if the compression fails or does not actually happen.
    Renaming does not take place if it gives a filename that already exists, nor if the file being processed is not a JPEG file.

  \e[4mresolution\e[0m
    A number indicating the size in pixels of the smallest side.
    Smaller images will not be enlarged, but they will still be potentially compressed.

  \e[4mfilename_or_directory\e[0m
    If a filename is given, the file is compressed. If a directory is given, all the JPEG files in it are compressed.
    Can't begins with a dash (-).
    If it is not given at all, ${0} process files and directories whose name are given on stdin, one by line.

\e[1mDESCRIPTION\e[0m
    Compress the given picture or the jpeg located in the given directory. If none is given, read filenames from stdin, one by line.

\e[1mCOMPRESSION\e[0m
    The file written is a JPEG with quality of 85% and chroma halved. This is a lossy compression to reduce file size. However, it is calculated with precision (so it is not suitable for creating thumbnail collections of large images). The steps of the compression are:

      1. The entire file is read in.
      2. Its color space is converted to a linear space (RGB). This avoids a color shift usually seen when resizing images.
      3. If the smallest side of the image is larger than the given resolution (in pixels), the image is resized so that this side has this size.
      4. The image is converted (back) to the standard sRGB color space.
      5. The image is converted to the frequency domain according to the JPEG algorithm using an accurate Discrete Cosine Transform (DCT is calculated with the float method) and encoded in JPEG 85% quality, chroma halved. (The JPEG produced is progressive: the loading is done on the whole image by improving the quality gradually)."
      
      



# Parameters for convert
READ_PARAMETERS='-auto-orient -colorspace RGB'
WRITE_PARAMETERS='-quality 85% -colorspace sRGB -interlace Plane -define jpeg:dct-method=float -sampling-factor 4:2:0'

# Return values
BAD_USAGE=1
CONVERT_ERR=2
NO_EXIST=3



#DEFAULTVARS
strip=""
recursive=false
resolution=""
inputFile=""
EXTENSION=""


#Process arguements and assign strip,EXTENSION and recursive
EXTRA=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    help|-h|--help)
	  echo -e "$USAGE"	
	  exit 0

      ;;
    -c|--strip)
	  strip="-strip"	
      shift # past argument
      ;;
	-e|--ext)	
      EXTENSION="$2"
      shift # past argument
      shift # past value
      ;;
    -r|--recursive)
      recursive=true
      shift # past argument
      ;;
    -*)  #if filename starts with -
      echo "Error: Filename cannot start with a hyphen. Please rename your file and process it using the updated name." >&2;
      exit $BAD_USAGE ;;

    *)    # other 
      EXTRA+=("$1") # save as an extra parameter
      shift # past argument
      ;;
  esac
done








#Functions


function print_without_formatting () {
    # Output the value of "$1" without formatting
    echo "$1" | sed 's/\\e\[[0-9;]\+m//g'
}


function is_jpeg () {
	#tests if file's mimetype is image/jpeg
	if file --mime-type "$1" | grep -q "image/jpeg"; then
		return 0
	else
		return 1
	fi

}


function is_valid_ext () {
	#Checks if EXTENSION is a jpeg extension
	declare -a validExts=("jpg" "jpeg" "jpe" "jif" "jfif" "jfi" "JPG" "JPEG" "JPE" "JIF" "JFIF" "JFI")
	for ext in "${validExts[@]}"; do
		if [[ "$ext" = "$EXTENSION" ]] ; then 
			return 0
		fi
	done
	return 1
}

function normalize () {
	#suppose inputFile = basename.ext. Function will rename basename.ext to basename.EXTENSION
	baseName=${inputFile%.*} #basename=inputfile
	renamedFile="$baseName.$EXTENSION" #renamedFile=basename.EXTENSION
    	[ "$inputFile" = "$renamedFile" ] && return 1  # if basename.ext=basename.EXTENSION (ie: file does not need normalizing)
    	ls |grep -q "$renamedFile" && echo "$inputFile" && return 1 #if renamed file already exists, echo out inputFile
		mv "$inputFile" "$renamedFile" && echo "$renamedFile" && return 0 #rename file, echo renamed file and return 0
}


function compressFile () {
	#Compresses file using convert. Normalizes if needs be.
	inputFile="$1"
    [ ! -z "$EXTENSION" ] && is_jpeg "$1" && normalize && inputFile="$renamedFile" #if extension exists and is jpeg, normalize and assign inputFile=renamedFile
    output=mktemp #name of future compressed file. Name does not exist in the machine
    convert $READ_PARAMETERS "$inputFile" -resize ${resolution}x${resolution} $strip $WRITE_PARAMETERS "$output" #compress function of imagemagic
    if [ $? ];then	#if convert was successful
        verify_compression && mv "$output" "$inputFile" #Verify compression, if verified replace original file with temp file.
        echo $inputFile
	else #if convert failed
		ls |grep -q "$output" && rm $output #if temp file was created, delete it
		echo "Error : $inputfile cannot be processed for compression">&2
		exit CONVERT_ERR
	fi

}

function verify_compression () {
	OriginalSize=`wc -c "$inputFile" | cut -d' ' -f1` #size of original file
	ConvertedSize=`wc -c "$output" | cut -d' ' -f1` 	#size of tempfile
	if [ $OriginalSize -gt $ConvertedSize ]; then #if tempfilesize is less than originalfilesize

		return 0
	else 
		rm "$output"
		echo "Could not compress $inputFile. File remains unchanged. potentially renamed if a valid extension change was requested">&2
		return 1
	fi
}

function processFolder() {

	#$1 = a folder to process 

	#loops through each file in the folder, if file is jpeg, it will be compressed
	for f in "$1"*; do 
	    if is_jpeg "${f}"; then
	    	compressFile "$f"  	
	    fi
	done
}

function processFolderRecursively() {
	#loops through each folder recursively, then processes each folder and finally itself.
	for f in "$@"* 	; do
	    if [ -d "$f" ]; then
	    	processFolderRecursively "$f/"  	
	    fi
	done
	processFolder "$1"
}

function readFiles() {
	while read -p "Input filename or foldername: " files
		do	
		if [ -z $files ]; then echo "Nothing was input. Press CTRL+D to exit or try again"
			else
			inputFile="$files"
			[ ! -d "$inputFile" ] && [ ! -f "$inputFile" ] && echo "Error: File is not a standard file or directory or does not exist" >&2 && exit $NO_EXIST
			[ -f "$inputFile" ]  && compressFile $inputFile #if file, compress file
			! [[ "${inputFile: -1}" = "/" ]] && inputFile+="/"
			$recursive && [ -d "$files" ]   && processFolderRecursively "$inputFile" #if folder and is recursive, launch processFolderRecursively
			! $recursive && [ -d "$files" ]   &&  processFolder "${inputFile}" #if folder and is not recursive, launch processFolder
		fi
    done
}



#script

#assign res and filename
#Assign resolution and inputFile 

set -- "${EXTRA[@]}" # restore extra arguements
[ -n "$3" ] &&  echo -e "Error: too many arguments parsed. $SHORT_USAGE">&2 && exit $BAD_USAGE #if there are more than 2 extra arguements -> error+display help
[[ $1 = *[!0-9]* ]] && [[ $2 = *[!0-9]* ]] && echo -e "Error: Resolution not inputed. $SHORT_USAGE">&2 &&exit $BAD_USAGE #if resolution was not detected->error+display help
#if both are numerical, $1=res and $2=inputFile
! [[ $1 = *[!0-9]* ]] && ! [[ $2 = *[!0-9]* ]] && resolution=$1 && inputFile=$2

#if 2nd param is nonnumerical, the 1st one must be numerical
if [[ $2 = *[!0-9]* ]]; then
	#$1 must be positive
	if [ "$1" > 0 ]; then
		resolution=$1
		inputFile=$2
	fi
else
	#$2 must be positive
	[ "$2" > 0 ] && resolution=$2  && inputFile=$1
fi
[ -z "$resolution" ] && echo "Error: Please enter a positive integer corresponding to your desired resolution" >&2 && exit 1 #If no positive integer was input
	


[ -z "$resolution" ] && echo "Error: Please enter a positive integer corresponding to your desired resolution" >&2 && exit 1 #If no positive integer was input
#if an extension change was requested, and extension input is not a jpeg extension, display error+help+exit
[ -n "$EXTENSION" ] && ! is_valid_ext $EXTENSION && echo "Error: Invalid extension. Extension must be one of .jpg .jpeg .jpe .jif .jfif .jfi" >&2 && exit $BAD_USAGE



#reading input
if [ -z "$inputFile" ] ; then readFiles #If inputFile does not exist, start reading stdin
else
#if file is not a directory nor a file,  display error+help+exit
[ ! -d "$inputFile" ] && [ ! -f "$inputFile" ] && echo "Error: $inputFile File is not a standard file nor a directory or does not exist" >&2 && exit $NO_EXIST

#if file, compress
[ -f "$inputFile" ] && compressFile "$inputFile"
#if file does not end in /, add it. Functions processFolderRecursively and processFolder need the backslash at the end to successfully loop through the folder.
! [[ "${inputFile: -1}" = "/" ]] && inputFile+="/"	
$recursive && [ -d "$inputFile" ] && processFolderRecursively "$inputFile" #if recursive, call processFolderRecursively
! $recursive && [ -d "$inputFile" ] && processFolder "$inputFile" #if nonrecursive, call processFolder
fi