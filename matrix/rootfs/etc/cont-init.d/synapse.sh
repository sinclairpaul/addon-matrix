#!/usr/bin/with-contenv bashio
# ==============================================================================
# Community Hass.io Add-ons: Matrix
# Configures the Matrix Synapse server
# ==============================================================================
readonly CONF="/config/matrix.yaml"
declare server_name

mv /opt/riot/config.sample.json config.json

if ! bashio::config.has_value 'server_name'; then
    bashio::log.fatal
    bashio::log.fatal 'You must specify your server name!'
    bashio::log.fatal 'This should be the hostname of your server'
    bashio::log.fatal 'without "http://" / "https://" and the port.'
    bashio::log.fatal 'Refer to the "server_name" option in the docs for more info.'
    bashio::log.fatal
    bashio::exit.nok
fi

server_name=$(bashio::config 'server_name')

if bashio::fs.file_exists "${CONF}"; then
    declare old_name
    old_name=$(yq read "${CONF}" 'server_name')
    if [[ "$old_name" != "$server_name" ]]; then
        bashio::log.fatal ''
        bashio::log.fatal 'The server_name has changed!'
        bashio::log.fatal 'Are you sure you want to do this?'
        bashio::log.fatal 'If so, delete the "matrix.yaml" file located in "/config" and restart the addon.'
        bashio::log.fatal 'WARNING: This will remove all rooms, users, chats and start afresh.'
        bashio::exit.nok
    fi
fi

if ! bashio::fs.file_exists "${CONF}"; then
    bashio::log.info "Config file at '/config/matrix.yaml' does not exist. Creating..."

    rm -f /share/matrix/matrix.db

    python3 -m synapse.app.homeserver \
        --server-name "$server_name" \
        --config-path /data/matrix/matrix.yaml \
        --generate-config \
        --generate-keys \
        --keys-directory /data/matrix \
        --report-stats=no

    mv /data/matrix/matrix.yaml "${CONF}"

    yq delete --inplace "${CONF}" 'listeners[1]'
    yq write --inplace "${CONF}" 'enable_registration' true
    yq write --inplace "${CONF}" 'database.args.database' '/share/matrix/matrix.db'
    yq write --inplace "${CONF}" 'media_store_path' '/share/matrix/media'
    yq write --inplace "${CONF}" 'uploads_path' '/share/matrix/uploads'
    yq write --inplace "${CONF}" 'max_upload_size' '200M'
fi

# Enure IPv6 is disabled on the main listener
yq delete --inplace "${CONF}" 'listeners[0].bind_addresses'
yq write --inplace "${CONF}" 'listeners[0].bind_addresses[0]' '0.0.0.0'

# This is the port Hass.io expects
yq write --inplace "${CONF}" 'listeners[0].port' '8448'

if bashio::config.true 'ssl'; then
    yq write --inplace "${CONF}" 'no_tls' false
    yq write --inplace "${CONF}" 'listeners[0].tls' true
    yq write --inplace "${CONF}" 'tls_certificate_path' "/ssl/$(bashio::config 'certfile')"
    yq write --inplace "${CONF}" 'tls_private_key_path' "/ssl/$(bashio::config 'keyfile')"
else
    yq write --inplace "${CONF}" 'no_tls' true
    yq write --inplace "${CONF}" 'listeners[0].tls' false
    # Synapse complains if there is not a certificate present even with no_tls set.
    # These are certificates obtained from lets encrypt generated by the above python command.
    yq write --inplace "${CONF}" 'tls_certificate_path' "/data/matrix/$server_name.tls.crt"
    yq write --inplace "${CONF}" 'tls_private_key_path' "/data/matrix/$server_name.tls.key"
fi

# Add warning to top of file
sed -i '1s/^/# Make sure you know what you are doing before editing this file!\n/' "${CONF}"
sed -i '1s/^/# Be aware that this file contains options that could potentially break the add-on.\n/' "${CONF}"
