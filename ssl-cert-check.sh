#!/usr/bin/env bash
## Regular Colors.

export BLUE='\e[1;94m'
export GREEN='\e[1;92m'
export RED='\e[1;91m'
export RESETCOLOR='\e[1;00m'
export BLACK='\e[0;30m'
export REGRED='\e[0;31m'
export REGGREEN='\e[0;32m'
export YELLOW='\e[0;33m'
export PURPLE='\e[0;35m'
export CYAN='\e[0;36m'
export WHITE='\e[0;37m'

## Bolder Colors

export BOLDBLACK='\e[1;30m'
export BOLDRED='\e[1;31m'
export BOLDGREEN='\e[1;32m'
export BOLDYELLOW='\e[1;33m'
export BOLDBLUE='\e[1;34m'
export BOLDPURPLE='\e[1;35m'
export BOLDCYAN='\e[1;36m'
export BOLDWHITE='\e[1;37m'

## Underlined Colors

export UNDERBLACK='\e[4;30m'
export UNDERRED='\e[4;31m'
export UNDERGREEN='\e[4;32m'
export UNDERYELLOW='\e[4;33m'
export UNDERBLUE='\e[4;34m'
export UNDERPURPLE='\e[4;35m'
export UNDERPURPLE='\e[4;36m'
export UNDERWHITE='\e[4;37m'

## Background colors

export BACKBLACK='\e[40m'
export BACKRED='\e[41m'
export BACKGREEN='\e[42m'
export BACKYELLOW='\e[43m'
export BACKBLUE='\e[44m'
export BACKPURPLE='\e[45m'
export BACKCYAN='\e[46m'
export BACKWHITE='\e[47m'
export TEXTRESET='\e[0m'


PROGRAMVERSION=4.14

# Cleanup temp files if they exist
trap cleanup EXIT INT TERM QUIT

PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/ssl/bin:/usr/sfw/bin
export PATH

ADMIN="root"

SENDER=""

# Number of days in the warning threshhold (cmdline: -x)
WARNDAYS=30

# If QUIET is set to TRUE, don't print anything on the console (cmdline: -q)
QUIET="FALSE"

# Don't send E-mail by default (cmdline: -a)
ALARM="FALSE"

# Don't run as a Nagios plugin by default (cmdline: -n)
NAGIOS="FALSE"

# Don't summarize Nagios output by default (cmdline: -N)
NAGIOSSUMMARY="FALSE"

# NULL out the PKCSDBPASSWD variable for later use (cmdline: -k)
PKCSDBPASSWD=""

# Type of certificate (PEM, DER, NET) (cmdline: -t)
CERTTYPE="pem"

# Location of system binaries
AWK=$(command -v awk)
DATE=$(command -v date)
GREP=$(command -v grep)
OPENSSL=$(command -v openssl)
PRINTF=$(command -v printf)
SED=$(command -v sed)
MKTEMP=$(command -v mktemp)
FIND=$(command -v find)

# Try to find a mail client
if [ -f /usr/bin/mailx ]; then
    MAIL="/usr/bin/mailx"
    MAILMODE="mailx"
elif [ -f /bin/mail ]; then
    MAIL="/bin/mail"
    MAILMODE="mail"
elif [ -f /usr/bin/mail ]; then
    MAIL="/usr/bin/mail"
    MAILMODE="mail"
elif [ -f /sbin/mail ]; then
    MAIL="/sbin/mail"
    MAILMODE="mail"
elif [ -f /usr/sbin/mail ]; then
    MAIL="/usr/sbin/mail"
    MAILMODE="mail"
elif [ -f /usr/sbin/sendmail ]; then
    MAIL="/usr/sbin/sendmail"
    MAILMODE="sendmail"
else
    MAIL="cantfindit"
    MAILMODE="cantfindit"
fi

# Return code used by nagios. Initialize to 0.
RETCODE=0

# Certificate counters and minimum difference. Initialize to 0.
SUMMARY_VALID=0
SUMMARY_WILL_EXPIRE=0
SUMMARY_EXPIRED=0
SUMMARY_MIN_DIFF=0
SUMMARY_MIN_DATE=
SUMMARY_MIN_HOST=
SUMMARY_MIN_PORT=

# Set the default umask to be somewhat restrictive
umask 077


#####################################################
# Purpose: Remove temporary files if the script doesn't
#          exit() cleanly
#####################################################
cleanup() {
    if [ -f "${CERT_TMP}" ]; then
        rm -f "${CERT_TMP}"
    fi

    if [ -f "${ERROR_TMP}" ]; then
     rm -f "${ERROR_TMP}"
    fi
}


#####################################################
### Send email
### Accepts three parameters:
###  $1 -> sender email address
###  $2 -> email to send mail
###  $3 -> Subject
###  $4 -> Message
#####################################################
send_mail() {

    FROM="${1}"
    TO="${2}"
    SUBJECT="${3}"
    MSG="${4}"

    case "${MAILMODE}" in
        "mail")
            echo "$MSG" | "${MAIL}" -r "$FROM" -s "$SUBJECT" "$TO"
            ;;
        "mailx")
            echo "$MSG" | "${MAIL}" -s "$SUBJECT" "$TO"
            ;;
        "sendmail")
            (echo "Subject:$SUBJECT" && echo "TO:$TO" && echo "FROM:$FROM" && echo "$MSG") | "${MAIL}" "$TO"
            ;;
        "*")
            echo "ERROR: You enabled automated alerts, but the mail binary could not be found."
            echo "FIX: Please modify the \${MAIL} and \${MAILMODE} variable in the program header."
            exit 1
            ;;
    esac
}

#############################################################################
# Purpose: Convert a date from MONTH-DAY-YEAR to Julian format
# Acknowledgements: Code was adapted from examples in the book
#                   "Shell Scripting Recipes: A Problem-Solution Approach"
#                   ( ISBN 1590594711 )
# Arguments:
#   $1 -> Month (e.g., 06)
#   $2 -> Day   (e.g., 08)
#   $3 -> Year  (e.g., 2006)
#############################################################################
date2julian() {

    if [ "${1}" != "" ] && [ "${2}" != "" ] && [ "${3}" != "" ]; then
        ## Since leap years add aday at the end of February,
        ## calculations are done from 1 March 0000 (a fictional year)
        d2j_tmpmonth=$((12 * $3 + $1 - 3))

        ## If it is not yet March, the year is changed to the previous year
        d2j_tmpyear=$(( d2j_tmpmonth / 12))

        ## The number of days from 1 March 0000 is calculated
        ## and the number of days from 1 Jan. 4713BC is added
        echo $(( (734 * d2j_tmpmonth + 15) / 24
                 - 2 * d2j_tmpyear + d2j_tmpyear/4
                 - d2j_tmpyear/100 + d2j_tmpyear/400 + $2 + 1721119 ))
    else
        echo 0
    fi
}

#############################################################################
# Purpose: Convert a string month into an integer representation
# Arguments:
#   $1 -> Month name (e.g., Sep)
#############################################################################
getmonth()
{
    case ${1} in
        Jan) echo 1 ;;
        Feb) echo 2 ;;
        Mar) echo 3 ;;
        Apr) echo 4 ;;
        May) echo 5 ;;
        Jun) echo 6 ;;
        Jul) echo 7 ;;
        Aug) echo 8 ;;
        Sep) echo 9 ;;
        Oct) echo 10 ;;
        Nov) echo 11 ;;
        Dec) echo 12 ;;
          *) echo 0 ;;
    esac
}

#############################################################################
# Purpose: Calculate the number of seconds between two dates
# Arguments:
#   $1 -> Date #1
#   $2 -> Date #2
#############################################################################
date_diff()
{
    if [ "${1}" != "" ] && [ "${2}" != "" ]; then
        echo $((${2} - ${1}))
    else
        echo 0
    fi
}

#####################################################################
# Purpose: Print a line with the expiraton interval
# Arguments:
#   $1 -> Hostname
#   $2 -> TCP Port
#   $3 -> Status of certification (e.g., expired or valid)
#   $4 -> Date when certificate will expire
#   $5 -> Days left until the certificate will expire
#   $6 -> Issuer of the certificate
#   $7 -> Common Name
#   $8 -> Serial Number
#####################################################################
prints()
{
    if [ "${NAGIOSSUMMARY}" = "TRUE" ]; then
        return
    fi

    if [ "${QUIET}" != "TRUE" ] && [ "${ISSUER}" = "TRUE" ] && [ "${VALIDATION}" != "TRUE" ]; then
        MIN_DATE=$(echo "$4" | "${AWK}" '{ printf "%3s %2d %4d", $1, $2, $4 }')
        if [ "${NAGIOS}" = "TRUE" ]; then
            ${PRINTF} "%-35s %-17s %-8s %-11s %s\n" "$1:$2" "$6" "$3" "$MIN_DATE" "|days=$5"
        else
            ${PRINTF} "%-35s %-17s %-8s %-11s %4d\n" "$1:$2" "$6" "$3" "$MIN_DATE" "$5"
        fi
    elif [ "${QUIET}" != "TRUE" ] && [ "${ISSUER}" = "TRUE" ] && [ "${VALIDATION}" = "TRUE" ]; then
        ${PRINTF} "%-35s %-35s %-32s %-17s\n" "$1:$2" "$7" "$8" "$6"

    elif [ "${QUIET}" != "TRUE" ] && [ "${VALIDATION}" != "TRUE" ]; then
        MIN_DATE=$(echo "$4" | "${AWK}" '{ printf "%3s %2d, %4d", $1, $2, $4 }')
        if [ "${NAGIOS}" = "TRUE" ]; then
            ${PRINTF} "%-47s %-12s %-12s %s\n" "$1:$2" "$3" "$MIN_DATE" "|days=$5"
        else
            ${PRINTF} "%-47s %-12s %-12s %4d\n" "$1:$2" "$3" "$MIN_DATE" "$5"
        fi
    elif [ "${QUIET}" != "TRUE" ] && [ "${VALIDATION}" = "TRUE" ]; then
        ${PRINTF} "%-35s %-35s %-32s\n" "$1:$2" "$7" "$8"
    fi
}


####################################################
# Purpose: Print a heading with the relevant columns
# Arguments:
#   None
####################################################
print_heading()
{
    if [ "${NOHEADER}" != "TRUE" ]; then
        if [ "${QUIET}" != "TRUE" ] && [ "${ISSUER}" = "TRUE" ] && [ "${NAGIOS}" != "TRUE" ] && [ "${VALIDATION}" != "TRUE" ]; then
            ${PRINTF} "\n%-35s %-17s %-8s %-11s %-4s\n" "Host" "Issuer" "Status" "Expires" "Days"
            echo "----------------------------------- ----------------- -------- ----------- ----"

        elif [ "${QUIET}" != "TRUE" ] && [ "${ISSUER}" = "TRUE" ] && [ "${NAGIOS}" != "TRUE" ] && [ "${VALIDATION}" = "TRUE" ]; then
            ${PRINTF} "\n%-35s %-35s %-32s %-17s\n" "Host" "Common Name" "Serial #" "Issuer"
            echo "----------------------------------- ----------------------------------- -------------------------------- -----------------"

        elif [ "${QUIET}" != "TRUE" ] && [ "${NAGIOS}" != "TRUE" ] && [ "${VALIDATION}" != "TRUE" ]; then
            ${PRINTF} "\n%-47s %-12s %-12s %-4s\n" "Host" "Status" "Expires" "Days"
            echo "----------------------------------------------- ------------ ------------ ----"

        elif [ "${QUIET}" != "TRUE" ] && [ "${NAGIOS}" != "TRUE" ] && [ "${VALIDATION}" = "TRUE" ]; then
            ${PRINTF} "\n%-35s %-35s %-32s\n" "Host" "Common Name" "Serial #"
            echo "----------------------------------- ----------------------------------- --------------------------------"
        fi
    fi
}

####################################################
# Purpose: Print a summary for nagios
# Arguments:
#   None
####################################################
print_summary()
{
    if [ "${NAGIOSSUMMARY}" != "TRUE" ]; then
        return
    fi

    if [ ${SUMMARY_WILL_EXPIRE} -eq 0 ] && [ ${SUMMARY_EXPIRED} -eq 0 ]; then
        ${PRINTF} "%s valid certificate(s)|days=%s\n" "${SUMMARY_VALID}" "${SUMMARY_MIN_DIFF}"

    elif [ ${SUMMARY_EXPIRED} -ne 0 ]; then
        ${PRINTF} "%s certificate(s) expired (%s:%s on %s)|days=%s\n" "${SUMMARY_EXPIRED}" "${SUMMARY_MIN_HOST}" "${SUMMARY_MIN_PORT}" "${SUMMARY_MIN_DATE}" "${SUMMARY_MIN_DIFF}"

    elif [ ${SUMMARY_WILL_EXPIRE} -ne 0 ]; then
        ${PRINTF} "%s certificate(s) will expire (%s:%s on %s)|days=%s\n" "${SUMMARY_WILL_EXPIRE}" "${SUMMARY_MIN_HOST}" "${SUMMARY_MIN_PORT}" "${SUMMARY_MIN_DATE}" "${SUMMARY_MIN_DIFF}"

    fi
}

#############################################################
# Purpose: Set returncode to value if current value is lower
# Arguments:
#   $1 -> New returncorde
#############################################################
set_returncode()
{
    if [ "${RETCODE}" -lt "${1}" ]; then
        RETCODE="${1}"
    fi
}

########################################################################
# Purpose: Set certificate counters and informations for nagios summary
# Arguments:
#   $1 -> Status of certificate (0: valid, 1: will expire, 2: expired)
#   $2 -> Hostname
#   $3 -> TCP Port
#   $4 -> Date when certificate will expire
#   $5 -> Days left until the certificate will expire
########################################################################
set_summary()
{
    if [ "${1}" -eq 0 ]; then
        SUMMARY_VALID=$((SUMMARY_VALID+1))
    elif [ "${1}" -eq 1 ]; then
        SUMMARY_WILL_EXPIRE=$((SUMMARY_WILL_EXPIRE+1))
    else
        SUMMARY_EXPIRED=$((SUMMARY_EXPIRED+1))
    fi

    if [ "${5}" -lt "${SUMMARY_MIN_DIFF}" ] || [ "${SUMMARY_MIN_DIFF}" -eq 0 ]; then
        SUMMARY_MIN_DATE="${4}"
        SUMMARY_MIN_DIFF="${5}"
        SUMMARY_MIN_HOST="${2}"
        SUMMARY_MIN_PORT="${3}"
    fi
}

##########################################
# Purpose: Describe how the script works
# Arguments:
#   None
##########################################
usage()
{
    echo "Usage: $0 [ -e email address ] [-E sender email address] [ -x days ] [-q] [-a] [-b] [-h] [-i] [-n] [-N] [-v]"
    echo "       { [ -s common_name ] && [ -p port] } || { [ -f cert_file ] } || { [ -c cert file ] } || { [ -d cert dir ] }"
    echo ""
    echo "  -a                : Send a warning message through E-mail"
    echo "  -b                : Will not print header"
    echo "  -c cert file      : Print the expiration date for the PEM or PKCS12 formatted certificate in cert file"
    echo "  -d cert directory : Print the expiration date for the PEM or PKCS12 formatted certificates in cert directory"
    echo "  -e E-mail address : E-mail address to send expiration notices"
    echo "  -E E-mail sender  : E-mail address of the sender"
    echo "  -f cert file      : File with a list of FQDNs and ports"
    echo "  -h                : Print this screen"
    echo "  -i                : Print the issuer of the certificate"
    echo "  -k password       : PKCS12 file password"
    echo "  -n                : Run as a Nagios plugin"
    echo "  -N                : Run as a Nagios plugin and output one line summary (implies -n, requires -f or -d)"
    echo "  -p port           : Port to connect to (interactive mode)"
    echo "  -q                : Don't print anything on the console"
    echo "  -s commmon name   : Server to connect to (interactive mode)"
    echo "  -S                : Print validation information"
    echo "  -t type           : Specify the certificate type"
    echo "  -V                : Print version information"
    echo "  -x days           : Certificate expiration interval (eg. if cert_date < days)"
    echo ""
}


##########################################################################
# Purpose: Connect to a server ($1) and port ($2) to see if a certificate
#          has expired
# Arguments:
#   $1 -> Server name
#   $2 -> TCP port to connect to
##########################################################################
check_server_status() {

    PORT="$2"
    case "$PORT" in
        smtp|25|submission|587) TLSFLAG="-starttls smtp";;
        pop3|110)               TLSFLAG="-starttls pop3";;
        imap|143)               TLSFLAG="-starttls imap";;
        ftp|21)                 TLSFLAG="-starttls ftp";;
        xmpp|5222)              TLSFLAG="-starttls xmpp";;
        xmpp-server|5269)       TLSFLAG="-starttls xmpp-server";;
        irc|194)                TLSFLAG="-starttls irc";;
        postgres|5432)          TLSFLAG="-starttls postgres";;
        mysql|3306)             TLSFLAG="-starttls mysql";;
        lmtp|24)                TLSFLAG="-starttls lmtp";;
        nntp|119)               TLSFLAG="-starttls nntp";;
        sieve|4190)             TLSFLAG="-starttls sieve";;
        ldap|389)               TLSFLAG="-starttls ldap";;
        *)                      TLSFLAG="";;
    esac

    if [ "${TLSSERVERNAME}" = "FALSE" ]; then
        OPTIONS="-connect ${1}:${2} $TLSFLAG"
    else
        OPTIONS="-connect ${1}:${2} -servername ${1} $TLSFLAG"
    fi

    echo "" | "${OPENSSL}" s_client $OPTIONS 2> "${ERROR_TMP}" 1> "${CERT_TMP}"

    if "${GREP}" -i "Connection refused" "${ERROR_TMP}" > /dev/null; then
        prints "${1}" "${2}" "Connection refused" "Unknown"
        set_returncode 3
    elif "${GREP}" -i "No route to host" "${ERROR_TMP}" > /dev/null; then
        prints "${1}" "${2}" "No route to host" "Unknown"
        set_returncode 3
    elif "${GREP}" -i "gethostbyname failure" "${ERROR_TMP}" > /dev/null; then
        prints "${1}" "${2}" "Cannot resolve domain" "Unknown"
        set_returncode 3
    elif "${GREP}" -i "Operation timed out" "${ERROR_TMP}" > /dev/null; then
        prints "${1}" "${2}" "Operation timed out" "Unknown"
        set_returncode 3
    elif "${GREP}" -i "ssl handshake failure" "${ERROR_TMP}" > /dev/null; then
        prints "${1}" "${2}" "SSL handshake failed" "Unknown"
        set_returncode 3
    elif "${GREP}" -i "connect: Connection timed out" "${ERROR_TMP}" > /dev/null; then
        prints "${1}" "${2}" "Connection timed out" "Unknown"
        set_returncode 3
    elif "${GREP}" -i "Name or service not known" "${ERROR_TMP}" > /dev/null; then
        prints "${1}" "${2}" "Unable to resolve the DNS name ${1}" "Unknown"
        set_returncode 3
    else
        check_file_status "${CERT_TMP}" "${1}" "${2}"
    fi
}

#####################################################
### Check the expiration status of a certificate file
### Accepts three parameters:
###  $1 -> certificate file to process
###  $2 -> Server name
###  $3 -> Port number of certificate
#####################################################
check_file_status() {

    CERTFILE="${1}"
    HOST="${2}"
    PORT="${3}"

    ### Check to make sure the certificate file exists
    if [ ! -r "${CERTFILE}" ] || [ ! -s "${CERTFILE}" ]; then
        echo "ERROR: The file named ${CERTFILE} is unreadable or doesn't exist"
        echo "ERROR: Please check to make sure the certificate for ${HOST}:${PORT} is valid"
        set_returncode 3
        return
    fi

    ### Grab the expiration date from the X.509 certificate
    if [ "${PKCSDBPASSWD}" != "" ]; then
        # Extract the certificate from the PKCS#12 database, and
        # send the informational message to /dev/null
        "${OPENSSL}" pkcs12 -nokeys -in "${CERTFILE}" \
                   -out "${CERT_TMP}" -clcerts -password pass:"${PKCSDBPASSWD}" 2> /dev/null

        # Extract the expiration date from the certificate
        CERTDATE=$("${OPENSSL}" x509 -in "${CERT_TMP}" -enddate -noout | \
                   "${SED}" 's/notAfter\=//')

        # Extract the issuer from the certificate
        CERTISSUER=$("${OPENSSL}" x509 -in "${CERT_TMP}" -issuer -noout | \
                     "${AWK}" 'BEGIN {RS=", " } $0 ~ /^O =/
                                 { print substr($0,5,17)}')

        ### Grab the common name (CN) from the X.509 certificate
        COMMONNAME=$("${OPENSSL}" x509 -in "${CERT_TMP}" -subject -noout | \
                     "${SED}" -e 's/.*CN = //' | \
                     "${SED}" -e 's/, .*//')

        ### Grab the serial number from the X.509 certificate
        SERIAL=$("${OPENSSL}" x509 -in "${CERT_TMP}" -serial -noout | \
                 "${SED}" -e 's/serial=//')
    else
        # Extract the expiration date from the ceriticate
        CERTDATE=$("${OPENSSL}" x509 -in "${CERTFILE}" -enddate -noout -inform "${CERTTYPE}" | \
                   "${SED}" 's/notAfter\=//')

        # Extract the issuer from the certificate
        CERTISSUER=$("${OPENSSL}" x509 -in "${CERTFILE}" -issuer -noout -inform "${CERTTYPE}" | \
                     "${AWK}" 'BEGIN {RS=", " } $0 ~ /^O =/ { print substr($0,5,17)}')

        ### Grab the common name (CN) from the X.509 certificate
        COMMONNAME=$("${OPENSSL}" x509 -in "${CERTFILE}" -subject -noout -inform "${CERTTYPE}" | \
                     "${SED}" -e 's/.*CN = //' | \
                     "${SED}" -e 's/, .*//')

        ### Grab the serial number from the X.509 certificate
        SERIAL=$("${OPENSSL}" x509 -in "${CERTFILE}" -serial -noout -inform "${CERTTYPE}" | \
                 "${SED}" -e 's/serial=//')
    fi

    ### Split the result into parameters, and pass the relevant pieces to date2julian
    set -- ${CERTDATE}
    MONTH=$(getmonth "${1}")

    # Convert the date to seconds, and get the diff between NOW and the expiration date
    CERTJULIAN=$(date2julian "${MONTH#0}" "${2#0}" "${4}")
    CERTDIFF=$(date_diff "${NOWJULIAN}" "${CERTJULIAN}")

    if [ "${CERTDIFF}" -lt 0 ]; then
        if [ "${ALARM}" = "TRUE" ]; then
            send_mail "${SENDER}" "${ADMIN}" "Certificate for ${HOST} \"(CN: ${COMMONNAME})\" has expired!" \
                "The SSL certificate for ${HOST} \"(CN: ${COMMONNAME})\" has expired!"
        fi

        prints "${HOST}" "${PORT}" "Expired" "${CERTDATE}" "${CERTDIFF}" "${CERTISSUER}" "${COMMONNAME}" "${SERIAL}"
        RETCODE_LOCAL=2

    elif [ "${CERTDIFF}" -lt "${WARNDAYS}" ]; then
        if [ "${ALARM}" = "TRUE" ]; then
            send_mail "${SENDER}" "${ADMIN}" "Certificate for ${HOST} \"(CN: ${COMMONNAME})\" will expire in ${CERTDIFF}-days or less" \
                "The SSL certificate for ${HOST} \"(CN: ${COMMONNAME})\" will expire on ${CERTDATE}"
        fi
        prints "${HOST}" "${PORT}" "Expiring" "${CERTDATE}" "${CERTDIFF}" "${CERTISSUER}" "${COMMONNAME}" "${SERIAL}"
        RETCODE_LOCAL=1

    else
        prints "${HOST}" "${PORT}" "Valid" "${CERTDATE}" "${CERTDIFF}" "${CERTISSUER}" "${COMMONNAME}" "${SERIAL}"
        RETCODE_LOCAL=0
    fi

    set_returncode "${RETCODE_LOCAL}"
    MIN_DATE=$(echo "${CERTDATE}" | "${AWK}" '{ print $1, $2, $4 }')
    set_summary "${RETCODE_LOCAL}" "${HOST}" "${PORT}" "${MIN_DATE}" "${CERTDIFF}"
}

#################################
### Start of main program
#################################
while getopts abc:d:e:E:f:hik:nNp:qs:St:Vx: option
do
    case "${option}" in
        a) ALARM="TRUE";;
        b) NOHEADER="TRUE";;
        c) CERTFILE=${OPTARG};;
        d) CERTDIRECTORY=${OPTARG};;
        e) ADMIN=${OPTARG};;
        E) SENDER=${OPTARG};;
        f) SERVERFILE=$OPTARG;;
        h) usage
           exit 1;;
        i) ISSUER="TRUE";;
        k) PKCSDBPASSWD=${OPTARG};;
        n) NAGIOS="TRUE";;
        N) NAGIOS="TRUE"
           NAGIOSSUMMARY="TRUE";;
        p) PORT=$OPTARG;;
        q) QUIET="TRUE";;
        s) HOST=$OPTARG;;
        S) VALIDATION="TRUE";;
        t) CERTTYPE=$OPTARG;;
        V) echo "${PROGRAMVERSION}"
           exit 0
        ;;
        x) WARNDAYS=$OPTARG;;
       \?) usage
           exit 1;;
    esac
done

### Check to make sure a openssl utility is available
if [ ! -f "${OPENSSL}" ]; then
    echo "ERROR: The openssl binary does not exist in ${OPENSSL}."
    echo "FIX: Please modify the \${OPENSSL} variable in the program header."
    exit 1
fi

### Check to make sure a date utility is available
if [ ! -f "${DATE}" ]; then
    echo "ERROR: The date binary does not exist in ${DATE} ."
    echo "FIX: Please modify the \${DATE} variable in the program header."
    exit 1
fi

### Check to make sure a grep and find utility is available
if [ ! -f "${GREP}" ] || [ ! -f "${FIND}" ]; then
    echo "ERROR: Unable to locate the grep and find binary."
    echo "FIX: Please modify the \${GREP} and \${FIND} variables in the program header."
    exit 1
fi

### Check to make sure the mktemp and printf utilities are available
if [ ! -f "${MKTEMP}" ] || [ -z "${PRINTF}" ]; then
    echo "ERROR: Unable to locate the mktemp or printf binary."
    echo "FIX: Please modify the \${MKTEMP} and \${PRINTF} variables in the program header."
    exit 1
fi

### Check to make sure the sed and awk binaries are available
if [ ! -f "${SED}" ] || [ ! -f "${AWK}" ]; then
    echo "ERROR: Unable to locate the sed or awk binary."
    echo "FIX: Please modify the \${SED} and \${AWK} variables in the program header."
    exit 1
fi

### Check to make sure a mail client is available it automated notifications are requested
if [ "${ALARM}" = "TRUE" ] && [ ! -f "${MAIL}" ]; then
    echo "ERROR: You enabled automated alerts, but the mail binary could not be found."
    echo "FIX: Please modify the ${MAIL} variable in the program header."
    exit 1
fi

# Send along the servername when TLS is used
if ${OPENSSL} s_client -help 2>&1 | grep '-servername' > /dev/null; then
    TLSSERVERNAME="TRUE"
else
    TLSSERVERNAME="FALSE"
fi

# Place to stash temporary files
CERT_TMP=$($MKTEMP /var/tmp/cert.XXXXXX)
ERROR_TMP=$($MKTEMP /var/tmp/error.XXXXXX)

### Baseline the dates so we have something to compare to
MONTH=$(${DATE} "+%m")
DAY=$(${DATE} "+%d")
YEAR=$(${DATE} "+%Y")
NOWJULIAN=$(date2julian "${MONTH#0}" "${DAY#0}" "${YEAR}")

### Touch the files prior to using them
if [ -n "${CERT_TMP}" ] && [ -n "${ERROR_TMP}" ]; then
    touch "${CERT_TMP}" "${ERROR_TMP}"
else
    echo "ERROR: Problem creating temporary files"
    echo "FIX: Check that mktemp works on your system"
    exit 1
fi

### If a HOST was passed on the cmdline, use that value
if [ "${HOST}" != "" ]; then
    print_heading
    check_server_status "${HOST}" "${PORT:=443}"
    print_summary
### If a file is passed to the "-f" option on the command line, check
### each certificate or server / port combination in the file to see if
### they are about to expire
elif [ -f "${SERVERFILE}" ]; then
    print_heading

    IFS=$'\n'
    for LINE in $(grep -E -v '(^#|^$)' "${SERVERFILE}")
    do
        HOST=${LINE%% *}
        PORT=${LINE##* }
        IFS=" "
        if [ "$PORT" = "FILE" ]; then
            check_file_status "${HOST}" "FILE" "${HOST}"
        else
            check_server_status "${HOST}" "${PORT}"
        fi
    done
    IFS="${OLDIFS}"
    print_summary
### Check to see if the certificate in CERTFILE is about to expire
elif [ "${CERTFILE}" != "" ]; then
    print_heading
    check_file_status "${CERTFILE}" "FILE" "${CERTFILE}"
    print_summary

### Check to see if the certificates in CERTDIRECTORY are about to expire
elif [ "${CERTDIRECTORY}" != "" ] && ("${FIND}" -L "${CERTDIRECTORY}" -type f > /dev/null 2>&1); then
    print_heading
    for FILE in $("${FIND}" -L "${CERTDIRECTORY}" -type f); do
        check_file_status "${FILE}" "FILE" "${FILE}"
    done
    print_summary
### There was an error, so print a detailed usage message and exit
else
    usage
    exit 1
fi

### Exit with a success indicator
if [ "${NAGIOS}" = "TRUE" ]; then
    exit "${RETCODE}"
else
    exit 0
fi
