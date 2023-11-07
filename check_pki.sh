#!/usr/bin/env sh


ok() {
    echo "$@"
    exit 0
}

warning() {
    echo "$@"
    exit 1
}

critical() {
    echo "$@"
    exit 2
}

unknown() {
    echo "$@"
    exit 3
}

[ $# -ne 1 ] && critical "{0} needs one and only one parameter: PKI directory."

PKI_DIRECTORY="$1"

[ -z "${PKI_DIRECTORY}" ] && critical "Please run ${0} whith PKI directory as parameter."
[ ! -d "${PKI_DIRECTORY}" ] && critical "PKI directory ${PKI_DIRECTORY} does not exist."

# Check for CA certificate

CA_CERTIFICATE="${PKI_DIRECTORY}/ca.crt"

[ ! -r "${CA_CERTIFICATE}" ] && critical "CA certificate missing."

openssl_verify() {
    CERTIFICATE="$1"
    shift

    if _output="$(openssl verify \
        -CAfile "${CA_CERTIFICATE}" \
        -x509_strict \
        -check_ss_sig \
        -policy_check \
        "$@" \
        "${CERTIFICATE}" 2>&1)"; then
        return 0
    fi

    _error_line="$(echo "${_output}" | grep -E '^error [0-9]+ at .*$')"
    _error_code=$(echo "${_error_line}" | sed -n -E 's/^error ([0-9]+) at .*$/\1/p')

    echo "${_error_line}"

    return "${_error_code}"
}

if ! output="$(openssl_verify \
    "${CA_CERTIFICATE}" \
    -attime "$(date +'%s' --date '+ 1 week')" \
    -auth_level 1)"
then
    critical "CA certificate will not be valid in one week: ${output}."
fi

if ! output="$(openssl_verify \
    "${CA_CERTIFICATE}" \
    -attime "$(date +'%s' --date '+ 1 month')" \
    -auth_level 1)"
then
    warning "CA certificate will not be valid in one month: ${output}."
fi

# Check for server certificates
for CERTIFICATE in "${PKI_DIRECTORY}"/*.crt; do
    # CA Certificate alreay checked.
    [ "${CERTIFICATE}" = "${CA_CERTIFICATE}" ] && continue

    # Do not check old CA certificate.
    [ "${CERTIFICATE}" = "${PKI_DIRECTORY}/ca-old.crt" ] && continue

    # Check only server certificates.
    if openssl x509 -noout -purpose -in "${CERTIFICATE}" | grep -q "SSL server : Yes"; then
        if ! output="$(openssl_verify \
            "${CA_CERTIFICATE}" \
            -attime "$(date +'%s' --date '+ 1 month')" \
            -auth_level 1)"
        then
            warning "Server certificate ${CERTIFICATE} will not be valid in ont month: ${output}."
        fi
    fi
done

# Check for other certificates
for CERTIFICATE in "${PKI_DIRECTORY}"/*.crt; do
    # CA Certificate alreay checked.
    [ "${CERTIFICATE}" = "${CA_CERTIFICATE}" ] && continue

    # Do not check old CA certificate.
    [ "${CERTIFICATE}" = "${PKI_DIRECTORY}/ca-old.crt" ] && continue

    # Server certificates already checked.
    openssl x509 -noout -purpose -in "${CERTIFICATE}" | grep -q "SSL server : Yes" && continue

    # Check certificate
    if ! output="$(openssl_verify \
        "${CA_CERTIFICATE}" \
        -attime "$(date +'%s' --date '+ 1 month')" \
        -auth_level 1)"
    then
        warning "Server certificate ${CERTIFICATE} will not be valid in ont month: ${output}."
    fi
done

ok "All certificates in ${PKI_DIRECTORY} are valid."
