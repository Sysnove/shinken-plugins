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


append() {
    FIRST="$1"
    SECOND="$2"

    if [ -z "${FIRST}" ]; then
        echo  "${SECOND}"
    else
        echo "${FIRST}, ${SECOND}"
    fi
}

[ $# -ne 1 ] && critical "{0} needs one and only one parameter: PKI directory."

PKI_DIRECTORY="$1"

[ -z "${PKI_DIRECTORY}" ] && critical "Please run ${0} whith PKI directory as parameter."
[ ! -d "${PKI_DIRECTORY}" ] && critical "PKI directory ${PKI_DIRECTORY} does not exist."

# Check for CA certificate
CA_CERTIFICATE="${PKI_DIRECTORY}/ca.crt"

[ ! -r "${CA_CERTIFICATE}" ] && critical "CA certificate missing."

CA_CERT_SUBJECT_HASH="$(openssl x509 -subject_hash -noout -in "${CA_CERTIFICATE}")"

CA_OLD_CERTIFICATE="${PKI_DIRECTORY}/ca-old.crt"

if [ -r "${CA_OLD_CERTIFICATE}" ]; then
    CA_OLD_CERT_SUBJECT_HASH="$(openssl x509 -subject_hash -noout -in "${CA_OLD_CERTIFICATE}")"
fi

# Check certificate validity.
for CERTIFICATE in "${PKI_DIRECTORY}"/*.crt; do
    # Do not check old CA certificate.
    [ "${CERTIFICATE}" = "${PKI_DIRECTORY}/ca-old.crt" ] && continue

    CERT_ISSUER_HASH="$(openssl x509 -issuer_hash -noout -in "${CERTIFICATE}")"

    # Detect CA
    if [ "${CERT_ISSUER_HASH}" = "${CA_OLD_CERT_SUBJECT_HASH}" ]; then
        CERT_CA="${CA_OLD_CERTIFICATE}"
    elif [ "${CERT_ISSUER_HASH}" = "${CA_CERT_SUBJECT_HASH}" ]; then
        CERT_CA="${CA_CERTIFICATE}"
    else
        NO_CA_CERTS="$(append "${NO_CA_CERTS}" "$(basename "${CERTIFICATE}")")"
        continue
    fi

    # Check expiration
    if ! openssl verify -CAfile "${CERT_CA}" "${CERTIFICATE}" >/dev/null 2>&1; then
        EXPIRED_CERTS="$(append "${EXPIRED_CERTS}" "$(basename "${CERTIFICATE}")")"
    fi

    if ! openssl verify -CAfile "${CERT_CA}" -attime "${IN_ONE_WEEK}" "${CERTIFICATE}" >/dev/null 2>&1; then
        NEAR_EXPIRATION_CERTS="$(append "${NEAR_EXPIRATION_CERTS}" "$(basename "${CERTIFICATE}")")"
    fi

    if ! openssl verify -CAfile "${CERT_CA}" -attime "${IN_ONE_MONTH}" "${CERTIFICATE}" >/dev/null 2>&1; then
        FAR_EXPIRATION_CERTS="$(append "${FAR_EXPIRATION_CERTS}" "$(basename "${CERTIFICATE}")")"
    fi
done


if [ -n "${EXPIRED_CERTS}" ]; then
    critical "Expired certificates: ${EXPIRED_CERTS}."
fi

if [ -n "${NEAR_EXPIRATION_CERTS}" ]; then
    critical "Those certificates expire in less than one week: ${NEAR_EXPIRATION_CERTS}."
fi

if [ -n "${FAR_EXPIRATION_CERTS}" ]; then
    warning "Those certificates expire in less than one month: ${FAR_EXPIRATION_CERTS}."
fi

if [ -n "${NO_CA_CERTS}" ]; then
    warning "Those certificates are not signed by know CA: ${NO_CA_CERTS}."
fi

ok "All certificates in ${PKI_DIRECTORY} are valid."
