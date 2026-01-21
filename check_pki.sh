#!/usr/bin/env sh

IN_ONE_WEEK="$(date +'%s' --date '+ 1 week')"
IN_ONE_MONTH="$(date +'%s' --date '+ 1 month')"

ok() {
    echo "OK: $*"
    exit 0
}

warning() {
    echo "WARNING: $*"
    exit 1
}

critical() {
    echo "CRITICAL: $*"
    exit 2
}

unknown() {
    echo "UNKNOWN: $*"
    exit 3
}

[ $# -ne 1 ] && critical "{0} needs one and only one parameter: PKI directory."

PKI_DIRECTORY="$1"

[ -z "${PKI_DIRECTORY}" ] && critical "Please run ${0} whith PKI directory as parameter."
[ ! -d "${PKI_DIRECTORY}" ] && critical "PKI directory ${PKI_DIRECTORY} does not exist."

# Check for CA certificate
CA_CERTIFICATE="${PKI_DIRECTORY}/ca.crt"

[ ! -r "${CA_CERTIFICATE}" ] && critical "CA certificate missing."

# Check certificate validity.
for CERTIFICATE in "${PKI_DIRECTORY}"/*.crt; do
    # Do not check old CA certificate.
    [ "${CERTIFICATE}" = "${PKI_DIRECTORY}/ca-old.crt" ] && continue

    # Retrieve Certificate purpose.
    if openssl verify -CAfile "${CA_CERTIFICATE}" -no_check_time -purpose crlsign "${CERTIFICATE}" >/dev/null 2>&1; then
        PURPOSE="CA"
    elif openssl verify -CAfile "${CA_CERTIFICATE}" -no_check_time -purpose sslserver "${CERTIFICATE}" >/dev/null 2>&1; then
        PURPOSE="Server"
    elif openssl verify -CAfile "${CA_CERTIFICATE}" -no_check_time -purpose sslclient "${CERTIFICATE}" >/dev/null 2>&1; then
        PURPOSE="Client"
    else
        openssl verify -CAfile "${CA_CERTIFICATE}" -no_check_time -purpose sslclient "${CERTIFICATE}"
        PURPOSE="Unknown"
    fi

    # Check expiration
    if ! openssl verify -CAfile "${CA_CERTIFICATE}" -attime "${IN_ONE_MONTH}" "${CERTIFICATE}" >/dev/null 2>&1; then
        warning "${PURPOSE} certificate ${CERTIFICATE} will expire in less than one month."
    fi

    if ! openssl verify -CAfile "${CA_CERTIFICATE}" -attime "${IN_ONE_WEEK}" "${CERTIFICATE}" >/dev/null 2>&1; then
        critical "${PURPOSE} certificate ${CERTIFICATE} will expire in less than one week."
    fi
done

ok "All certificates in ${PKI_DIRECTORY} are valid."
