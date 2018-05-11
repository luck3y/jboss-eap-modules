source ${JBOSS_HOME}/bin/launch/openshift-node-name.sh
source $JBOSS_HOME/bin/launch/logging.sh

function prepareEnv() {
  unset OPENSHIFT_KUBE_PING_NAMESPACE
  unset OPENSHIFT_KUBE_PING_LABELS
  unset KUBERNETES_LABELS
  unset KUBERNETES_NAMESPACE
  unset OPENSHIFT_DNS_PING_SERVICE_NAME
  unset OPENSHIFT_DNS_PING_SERVICE_PORT
  unset JGROUPS_CLUSTER_PASSWORD
  unset JGROUPS_PING_PROTOCOL
  unset NODE_NAME
}

function configure() {
  configure_ha
}

function check_view_pods_permission() {
    if [ -n "${KUBERNETES_NAMESPACE+_}" ]; then
        local CA_CERT="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
        local CURL_CERT_OPTION
        pods_url="https://${KUBERNETES_SERVICE_HOST:-kubernetes.default.svc}:${KUBERNETES_SERVICE_PORT:-443}/api/${OPENSHIFT_KUBE_PING_API_VERSION:-v1}/namespaces/${KUBERNETES_NAMESPACE}/pods"
        if [ -n "${KUBERNETES_LABELS}" ]; then
            pods_labels="labels=${KUBERNETES_LABELS}"
        else
            pods_labels=""
        fi

        # make sure the cert exists otherwise use insecure connection
        if [ -f "${CA_CERT}" ]; then
            CURL_CERT_OPTION="--cacert ${CA_CERT}"
        else
            CURL_CERT_OPTION="-k"
        fi
        pods_auth="Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
        pods_code=$(curl --noproxy "*" -s -o /dev/null -w "%{http_code}" -G --data-urlencode "${pods_labels}" ${CURL_CERT_OPTION} -H "${pods_auth}" ${pods_url})
        if [ "${pods_code}" = "200" ]; then
            log_info "Service account has sufficient permissions to view pods in kubernetes (HTTP ${pods_code}). Clustering will be available."
        elif [ "${pods_code}" = "403" ]; then
            log_warning "Service account has insufficient permissions to view pods in kubernetes (HTTP ${pods_code}). Clustering might be unavailable. Please refer to the documentation for configuration."
        else
            log_warning "Service account unable to test permissions to view pods in kubernetes (HTTP ${pods_code}). Clustering might be unavailable. Please refer to the documentation for configuration."
        fi
    else
        log_warning "Environment variable KUBERNETES_NAMESPACE undefined. Clustering will be unavailable. Please refer to the documentation for configuration."
    fi
}

function validate_dns_ping_settings() {
  if [ "x$OPENSHIFT_DNS_PING_SERVICE_NAME" = "x" ]; then
    log_warning "Environment variable OPENSHIFT_DNS_PING_SERVICE_NAME undefined. Clustering will be unavailable. Please refer to the documentation for configuration."
  fi
}

function validate_ping_protocol() {
  if [ "$1" = "kubernetes.KUBE_PING" ] || [ "$1" = "openshift.KUBE_PING" ]; then
    check_view_pods_permission
  elif [ "$1" = "dns.DNS_PING" ] || [ "$1" = "openshift.DNS_PING" ]; then
    validate_dns_ping_settings
  else
    log_warning "Unknown protocol specified for JGroups discovery protocol: $1.  Expecting one of: kubernetes.KUBE_PING, dns.DNS_PING, openshift.KUBE_PING or openshift.DNS_PING."
  fi
}

function configure_ha() {
  # Set HA args

  log_info "XXX: OKPN: $OPENSHIFT_KUBE_PING_NAMESPACE OKPL: $OPENSHIFT_KUBE_PING_LABELS"
  log_info "XXX: KN: $KUBERNETES_NAMESPACE KL: $KUBERNETES_LABELS"
  # deprecation
  if [ -n "$OPENSHIFT_KUBE_PING_NAMESPACE" ] && [ -z "$KUBERNETES_NAMESPACE"]; then
    log_info "Setting KUBERNETES_NAMESPACE to $OPENSHIFT_KUBE_PING_NAMESPACE"
    export KUBERNETES_NAMESPACE="$OPENSHIFT_KUBE_PING_NAMESPACE"
    #unset OPENSHIFT_KUBE_PING_NAMESPACE
  elif [ -n "$OPENSHIFT_KUBE_PING_NAMESPACE" ] && [ -n "$KUBERNETES_NAMESPACE"]; then
    # use the KUBE one, drop the OS one, and warn the user
    log_warning "Both OPENSHIFT_KUBE_PING_NAMESPACE and KUBERNETES_NAMESPACE set, ignoring OPENSHIFT_KUBE_PING_NAMESPACE"
    #unset OPENSHIFT_KUBE_PING_NAMESPACE
  fi

  if [ -n "$OPENSHIFT_KUBE_PING_LABELS" ] && [ -z "$KUBERNETES_LABELS"]; then
    log_info "Setting KUBERNETES_LABELS to $OPENSHIFT_KUBE_PING_LABELS"
    export KUBERNETES_LABELS="$OPENSHIFT_KUBE_PING_LABELS"
    #unset OPENSHIFT_KUBE_PING_LABELS
  elif [ -n "$OPENSHIFT_KUBE_PING_LABELS" ] && [ -n "$KUBERNETES_LABELS"]; then
    # use the KUBE one, drop the OS one, and warn the user
    log_warning "Both OPENSHIFT_KUBE_PING_LABELS and KUBERNETES_LABELS set, ignoring OPENSHIFT_KUBE_PING_LABELS"
    #unset OPENSHIFT_KUBE_PING_LABELS
  fi

  IP_ADDR=`hostname -i`
  JBOSS_HA_ARGS="-b ${IP_ADDR} -bprivate ${IP_ADDR}"

  init_node_name

  JBOSS_HA_ARGS="${JBOSS_HA_ARGS} -Djboss.node.name=${JBOSS_NODE_NAME}"

  if [ -z "${JGROUPS_CLUSTER_PASSWORD}" ]; then
      log_warning "No password defined for JGroups cluster. AUTH protocol will be disabled. Please define JGROUPS_CLUSTER_PASSWORD."
      JGROUPS_AUTH="<!--WARNING: No password defined for JGroups cluster. AUTH protocol has been disabled. Please define JGROUPS_CLUSTER_PASSWORD. -->"
  else
    JGROUPS_AUTH="\n\
                <protocol type=\"AUTH\">\n\
                    <property name=\"auth_class\">org.jgroups.auth.MD5Token</property>\n\
                    <property name=\"token_hash\">SHA</property>\n\
                    <property name=\"auth_value\">$JGROUPS_CLUSTER_PASSWORD</property>\n\
                </protocol>\n"
  fi

  local ping_protocol=${JGROUPS_PING_PROTOCOL:-kubernetes.KUBE_PING}
  local ping_protocol_element
  local selected_ping_protocol="$ping_protocol"

  # compat with previous values
  if [ "openshift.DNS_PING" = "$ping_protocol" ]; then
    selected_ping_protocol="dns.DNS_PING"
  elif [ "openshift.KUBE_PING" = "$ping_protocol" ]; then
    selected_ping_protocol="kubernetes.KUBE_PING"
  fi

  log_info "XXX ping: $ping_protocol : spp: $selected_ping_protocol"
  validate_ping_protocol "${selected_ping_protocol}"

  if [ "$selected_ping_protocol" = "kubernetes.KUBE_PING" ]; then
    ping_protocol_element="<protocol type=\"${selected_ping_protocol}\"/>"
  elif [ "$selected_ping_protocol" = "dns.DNS_PING" ]; then
    local svc_name="$OPENSHIFT_DNS_PING_SERVICE_PORT._tcp.$OPENSHIFT_DNS_PING_SERVICE_NAME"
    ping_protocol_element="<protocol type=\"${selected_ping_protocol}\"><property name=\"dns_query\">${svc_name}</property><property name=\"dns_record_type\">SRV</property></protocol>"
    log_info "PPE: ${ping_protocol_element}"
  fi

  log_info "XXX: ping_pe: $ping_protocol_element"
  sed -i "s|<!-- ##JGROUPS_AUTH## -->|${JGROUPS_AUTH}|g" $CONFIG_FILE
  log_info "Configuring JGroups discovery protocol to ${selected_ping_protocol}"
  sed -i "s|<!-- ##JGROUPS_PING_PROTOCOL## -->|${ping_protocol_element}|g" $CONFIG_FILE

}

