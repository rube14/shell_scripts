#!/bin/bash

usage(){
    cat <<-EOF
	Usage: $0  -i  RUN_POSITION[#TAG[_SPLIT]]  [ -k|d|f|n|r|o|c VALUE ]  [ -h|H ]

	Example: $0 -i 12345_1#1_ysplit

	Use $0 -H for details about options.

	email to <rb11@sanger.ac.uk> to report bugs.
	EOF
}


morehelp(){
    cat <<-EOF
	usage: $0 options
	
	This script downloads bam|cram files from iRODS
	
	OPTIONS
	
	Required:

	   -i <rpt|file>    Input id ( RUN_POSITION[#TAG[_SPLIT]] ) or a targets file.

	OR:

	   -r <run>         Run
	
	Optional:

	   -p <position>    Lane

	   -t <tag>         Tag
	
	   -k <full path>   Full path to keytabs directory. Use env KEYTABPATH for default
	                    path otherwise one is required.
	
	   -d <savedir>     Download directory; default is ./<RUN>; If -i targetsfile you
	                    can use -c <column n>.
	
	   -f <format>      Download format: 
	
	                    -f b  BAM file, if exists, otherwise CRAM->BAM will be 
	                          enforced unless -n is used
	
	                    -f c  CRAM file. This is the default
	
	                    -f f  Files in FASTQ format (.fq.gz)
	
	                    -f i  Download index file only (.cram.crai or .bai) if both
	                          files are wanted then use -f c|b and -o i
	
	                    -f t  Tophat files only, extracting accepted_hits.bam from
	                          CRAM or BAM plus other files as specified by option -o
	
	   -n <number>      Record (line number) inside targets file to be processed
	
	   -R <reference>   Only needed if -f f and BAM is not present in iRODS
	
	   -o <options>     Use with  -f t  to specify extra files to be downloaded. 
	                    In all cases files will be saved into ./tophat/<runid>/<rpt> 
	                    and -d is ignored:
	
	                    -o a  All available Tophat files: accepted_hits.bam, 
	                          unmapped.bam, *.bed
	
	                    -o b  Tophat's BAMs: accepted_hits.bam and unmapped.bam
	
	                    -o h  Tophat's accepted_hits.bam only (default)
	
	                    Use with  -f c|b  to download:
	
	                    -o a  All target tags if available (No PhiX/split files)
	
	                    -o i  Index file: .cram.crai or .bai correspondingly
	
	   -c <column n>    Use to indicate the column in the targets file to be used
	                    as <SAVEDIR> if empty then ./<RUN>.
	
	   -h               Show usage message.
	
	   -H               Show this message.
	
	EOF
}
#	   -f <format/file> Download format: <b>am, <c>ram, <f>astq (.fq.gz), <t>ophat, <o>ther; default: c.
# 	   -o <options>     Only needed if -f = o: <m>d5. Not implemented yet:  <i>ndex (bai/crai), <p>hiX, <s>tats, seqch<k>sum

#die() { echo >&2 -e "\nERROR: $@\n"; exit 1; }
#printcmd_and_run() { echo "COMMAND: $@"; "$@"; code=$?; [ $code -ne 0 ] && die "command [$*] failed with error code $code"; }

while getopts ":hHi:d:f:n:R:t:o:c:k:" OPTION; do
    case $OPTION in
        c)
            TARGETSCOLUMN=$OPTARG;;
        d)
            SDIR=$OPTARG;;
        f)
            FORMAT=$OPTARG;;
        h)
            usage; exit 1;;
        H)
            morehelp; exit 1;;
        i)
            TARGET=$OPTARG;;
        k)
            KEYTABPATH=$OPTARG;;
        n)
            RECNO=$OPTARG;;
        o)
            FOPTION=$OPTARG;;
        p)
            POSITION=$OPTARG;;
        r)
            RUNID=$OPTARG;;
        t)
            TAGINDEX=$OPTARG;;
        R)
            REFERENCE=$OPTARG;;
        \?)
            echo "Invalid option: -$OPTARG" >&2; exit 1;;
        :)
            echo "Option -$OPTARG requires an argument." >&2; exit 1;;
    esac
done

exitmessage(){
    declare EXITMESG=$1
    declare EXITCODE=$2
    if [ $EXITCODE -eq 0 ]; then
        >&1 printf '\n%s\n' "$EXITMESG"
    else
        >&2 printf '\n%s\n' "$EXITMESG"
    fi
    exit $EXITCODE
}


defaultgzlevel=9


[ -z "$FORMAT" ] && FORMAT=c
[ -n "$FORMAT" ] && [[ ! $FORMAT =~ ^[bcftoi]$ ]] && exitmessage "-f: Wrong output format: $FORMAT" 2


wrongfoption=0
if [ "$FORMAT" = "t" ]; then
    [ -z "$FOPTION" ] && FOPTION=h
    [[ ! $FOPTION =~ ^[abh]$ ]] && wrongfoption=1
elif [[ $FORMAT =~ c|b ]] && [ -n "$FOPTION" ]; then
    [ -z "$FOPTION" ] && FOPTION=""
    [[ ! $FOPTION =~ ^i$ ]] && wrongfoption=1
fi
[ "$wrongfoption" -eq "1" ] && exitmessage "-o: Wrong file-type option for -f $FORMAT: $FOPTION" 2


if [ -z "$TARGET" ]; then

    usage
    exit 1

elif [ -e "$TARGET" ]; then

    if [ -z "$LSB_JOBINDEX" ]; then
        if [ -n "$RECNO" ]; then
            [ -n "$RECNO" ] && [[ $RECNO =~ ^[0-9]+$ ]] || exitmessage "-n: not a digit: $RECNO" 2
        else
            exitmessage "ERROR: Env variable LSB_JOBINDEX not set. Use -n?" 1            
        fi
    fi

    LINE=${LSB_JOBINDEX:-$RECNO}

    RUN=`head -n ${LINE} ${TARGET} | tail -1 | awk 'BEGIN { FS = "\t" } ; {print $2}'`
    POS=`head -n ${LINE} ${TARGET} | tail -1 | awk 'BEGIN { FS = "\t" } ; {print $3}'`
    TAG=`head -n ${LINE} ${TARGET} | tail -1 | awk 'BEGIN { FS = "\t" } ; {print $4}'`

    if [ -n "$TARGETSCOLUMN" ]; then
        
        [[ ! $TARGETSCOLUMN =~ ^[[:digit:]]?$ ]] && exitmessage "-c: Column not a number -c: $TARGETSCOLUMN" 1

        SDIR=`head -n ${LINE} ${TARGET} | tail -1 | awk -v col=$TARGETSCOLUMN 'BEGIN { FS = "\t" } ; {print $col}'`
        
    fi
           
else

    regex='^([[:digit:]]*)_([[:digit:]]*)(_([[:alpha:]]*))?(#([[:digit:]]*))?(_([[:alpha:]]*))?'

    if [[ "$TARGET" =~ $regex ]]; then
        RUN="${BASH_REMATCH[1]}";
        POS="${BASH_REMATCH[2]}";
        TAG="${BASH_REMATCH[6]}";
        SPL="${BASH_REMATCH[8]}";
    else
        exitmessage "The run id '$TARGET' doesn't look right. Example: 14940_3#34_human" 1
    fi
    
fi

# echo DEBUG: run: $RUN  pos: $POS  tag: $TAG  spl: $SPL

XAMID=$RUN\_$POS

[ -n "$TAG" ] && XAMID=$RUN\_$POS\#$TAG
[ -n "$SPL" ] && XAMID=$RUN\_$POS\#$TAG\_$SPL

exit


if env | grep -q ^KEYTABPATH=; then
    echo "Using keytabs found in $KEYTABPATH"
    USER=`whoami`
    KEYTABFILE=${USER}.keytab
    if [ -d "$KEYTABPATH" ] && [ -e "${KEYTABPATH}/${KEYTABFILE}" ]; then
        echo "COMMAND: /usr/bin/kinit  ${USER}\@INTERNAL.SANGER.AC.UK -k -t ${KEYTABPATH}/${KEYTABFILE}"
        /usr/bin/kinit  ${USER}\@INTERNAL.SANGER.AC.UK -k -t  "${KEYTABPATH}/${KEYTABFILE}"
    else
        exitmessage "-k: No keytab found: cannot access ${KEYTABPATH}/${KEYTABFILE}: no such file or directory. Use KEYTABPATH env var?" 1
        # example: /nfs/gapi/data/keytabs/${USER}.keytab
    fi
else
    if [ -z "$KEYTABPATH" ]; then
        exitmessage "-k: No keytab found: cannot access ${KEYTABPATH}/${KEYTABFILE}: no such file or directory. Use KEYTABPATH env var?" 1
    fi
fi


LSBAM="$(ils /seq/${RUN}/${XAMID}.bam 2>&1)"
NOBAM=$?

if [ "$NOBAM" -eq "4" ]; then
    iformat=cram
    ixformat=cram.crai
elif [ "$NOBAM" -eq "0" ]; then
    iformat=bam
    ixformat=bai
else
    exitmessage "Error trying to get bam/cram file for ${XAMID}: $LSBAM" 1
fi



if [ -z "$SDIR" ]; then
    SDIR=${RUN}
else
    [ "$SDIR" != "$RUN" ] && SDIR+=/${RUN}
fi

# echo DEBUG: directory: $SDIR; exit 0

mkdir -p $SDIR

RET_CODE=0

case "$FORMAT" in
    b)
        if [ "$NOBAM" -eq "4" ]; then
            echo "No bam format file present in iRODS for ${XAMID}: $LSBAM"
            echo "Converting cram->bam ..."
            echo "COMMAND: /software/irods/icommands/bin/iget -K /seq/${RUN}/${XAMID}.cram - | /software/solexa/bin/scramble -I cram -O bam - ${SDIR}/${XAMID}.bam"
            /software/irods/icommands/bin/iget -K /seq/${RUN}/${XAMID}.cram - | /software/solexa/bin/scramble -I cram -O bam - ${SDIR}/${XAMID}.bam
            RET_CODE=$?
            if [ "$FOPTION" = "i" ]; then
                echo "COMMAND: /software/npg/bin/samtools1 index ${SDIR}/${XAMID}.bam"
                /software/npg/bin/samtools1 index ${SDIR}/${XAMID}.bam
                [ "$?" -ne "0" ] && echo "WARNING: Failed to create index file for ${SDIR}/${XAMID}.bam"
            fi
        elif [ "$NOBAM" -eq "0" ]; then
            echo "COMMAND: /software/irods/icommands/bin/iget -KPvf /seq/${RUN}/${XAMID}.bam ${SDIR}/${XAMID}.bam"
            /software/irods/icommands/bin/iget -KPvf /seq/${RUN}/${XAMID}.bam ${SDIR}/${XAMID}.bam
            RET_CODE=$?
            if [ "$FOPTION" = "i" ]; then
                echo "COMMAND: /software/irods/icommands/bin/iget -KPvf /seq/${RUN}/${XAMID}.bai ${SDIR}/${XAMID}.bai"
                /software/irods/icommands/bin/iget -KPvf /seq/${RUN}/${XAMID}.bai ${SDIR}/${XAMID}.bai
                [ "$?" -ne "0" ] && echo "WARNING: Failed to download index file for ${SDIR}/${XAMID}.bam"
            fi
        fi
        ;;
    c)
        echo "COMMAND: /software/irods/icommands/bin/iget -KPvf /seq/${RUN}/${XAMID}.cram ${SDIR}/${XAMID}.cram"
        /software/irods/icommands/bin/iget -KPvf /seq/${RUN}/${XAMID}.cram ${SDIR}/${XAMID}.cram
        RET_CODE=$?
        if [ "$FOPTION" = "i" ]; then
            echo "COMMAND: /software/irods/icommands/bin/iget -KPvf /seq/${RUN}/${XAMID}.${ixformat} ${SDIR}/${XAMID}.${ixformat}"
            /software/irods/icommands/bin/iget -KPvf /seq/${RUN}/${XAMID}.${ixformat} ${SDIR}/${XAMID}.${ixformat}
            [ "$?" -ne "0" ] && echo "WARNING: Failed to download index file for ${SDIR}/${XAMID}.bam"
        fi
        ;;
    f)
        if [ "$NOBAM" -eq "4" ]; then
            REFERENCEOPTION=""
            if [ -z "$REFERENCE" ]; then
                exitmessage "-f: A reference is needed: -r $REFERENCE ." 1
            else
                REFERENCEOPTION="reference=$REFERENCE"
            fi
        fi
        SDIR=./bamfq/$RUN
        FQ1=$SDIR/${XAMID}_1.fq.gz
        FQ2=$SDIR/${XAMID}_2.fq.gz
        mkdir -p $SDIR
        echo "COMMAND: /software/irods/icommands/bin/iget /seq/${RUN}/${XAMID}.$iformat - | \
                       /software/npg/bin/bamsort SO=queryname level=0 inputformat=$iformat $REFERENCEOPTION outputformat=bam index=0 tmpfile=./bamfq/ | \
                       /software/npg/bin/bamtofastq exclude=QCFAIL gz=1 level=$defaultgzlevel F=$FQ1 F2=$FQ2"
        /software/irods/icommands/bin/iget /seq/${RUN}/${XAMID}.$iformat - | \
            /software/npg/bin/bamsort SO=queryname level=0 inputformat=$iformat $REFERENCEOPTION outputformat=bam index=0 tmpfile=./bamfq/ | \
            /software/npg/bin/bamtofastq exclude=QCFAIL gz=1 level=$defaultgzlevel F=$FQ1 F2=$FQ2
        RET_CODE=$?
        ;;
    i)
        echo "COMMAND: /software/irods/icommands/bin/iget -KPvf /seq/${RUN}/${XAMID}.${ixformat} ${SDIR}/${XAMID}.${ixformat}"
        /software/irods/icommands/bin/iget -KPvf /seq/${RUN}/${XAMID}.${ixformat} ${SDIR}/${XAMID}.${ixformat}
        RET_CODE=$?
        ;;       
    t)
        SDIR=./tophat/$RUN/$XAMID
        mkdir -p $SDIR
        ret_code_junc=0
        ret_code_dels=0
        ret_code_hits=0
        ret_code_unmp=0
        echo "COMMAND: /software/npg/bin/samtools1 view -bh -F 0x4 -o ${SDIR}/accepted_hits.bam irods:/seq/${RUN}/${XAMID}.$iformat"
        ACCEPTEDHITSFILE="$(/software/npg/bin/samtools1 view -bh -F 0x4 -o ${SDIR}/accepted_hits.bam irods:/seq/${RUN}/${XAMID}.$iformat 2>&1)"
        ret_code_hits=$?
        if [[ $FOPTION =~ a|b ]] ; then
            echo "COMMAND: /software/npg/bin/samtools1 view -bh -f 0x4 -o ${SDIR}/unmapped.bam irods:/seq/${RUN}/${XAMID}.$iformat"
            UNMAPPEDFILE="$(/software/npg/bin/samtools1 view -bh -f 0x4 -o ${SDIR}/unmapped.bam irods:/seq/${RUN}/${XAMID}.$iformat 2>&1)"
            ret_code_unmp=$?
        fi
        if [ "$FOPTION" = "a" ]; then
            echo "COMMAND: /software/irods/icommands/bin/iget -KPvf /seq/${RUN}/${XAMID}.junctions.bed  ${SDIR}/junctions.bed"
            JUNCTIONSFILE="$(/software/irods/icommands/bin/iget -KPvf /seq/${RUN}/${XAMID}.junctions.bed  ${SDIR}/junctions.bed 2>&1)"
            ret_code_junc=$?
            echo "COMMAND: /software/irods/icommands/bin/iget -KPvf /seq/${RUN}/${XAMID}.deletions.bed  ${SDIR}/deletions.bed"
            DELETIONSFILE="$(/software/irods/icommands/bin/iget -KPvf /seq/${RUN}/${XAMID}.deletions.bed  ${SDIR}/deletions.bed 2>&1)"
            ret_code_dels=$?
        fi
        let "RET_CODE = ret_code_junc + ret_code_dels + ret_code_hits + ret_code_unmp"
        if [ "$RET_CODE" -ne "0" ]; then
            echo "-f t: One or more files failed to download"
            [ "$ret_code_junc" -ne "0" ] && echo "iget: $JUNCTIONSFILE"
            [ "$ret_code_dels" -ne "0" ] && echo "iget: $DELETIONSFILE"
            [ "$ret_code_hits" -ne "0" ] && echo "iget: $ACCEPTEDHITSFILE"
            [ "$ret_code_unmp" -ne "0" ] && echo "iget: $UNMAPPEDFILE"
        fi
        ;;
esac

exit $RET_CODE
