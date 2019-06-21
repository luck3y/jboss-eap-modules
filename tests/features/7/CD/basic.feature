@jboss-eap-7-tech-preview/eap-cd-openshift
Feature: Common EAP CD tests

  # https://issues.jboss.org/browse/CLOUD-180
  Scenario: Check if image version and release is printed on boot
    When container is ready
    Then container log should contain Running jboss-eap-7-tech-preview/eap-cd-openshift image, version

  Scenario: Check that the labels are correctly set
    Given image is built
    Then the image should contain label com.redhat.component with value jboss-eap-7-eap-cd-openshift-container
     And the image should contain label name with value jboss-eap-7-tech-preview/eap-cd-openshift
     And the image should contain label io.openshift.expose-services with value 8080:http
     And the image should contain label io.openshift.tags with value builder,javaee,eap,eap7

  # https://issues.jboss.org/browse/CLOUD-204
  Scenario: Check if kube ping protocol is used by default
    When container is ready
    # 2 matches, one for TCP, one for UDP
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 2 elements on XPath //*[local-name()='protocol'][@type='kubernetes.KUBE_PING']
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()='protocol'][@type='dns.DNS_PING']
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()="protocol"][@type="openshift.KUBE_PING"]
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()="protocol"][@type="openshift.DNS_PING"]

  # https://issues.jboss.org/browse/CLOUD-1958
  Scenario: Check if kube ping protocol is used when specified
    When container is started with env
      | variable                             | value           |
      | JGROUPS_PING_PROTOCOL                | openshift.KUBE_PING     |
    # 2 matches, one for TCP, one for UDP
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 2 elements on XPath //*[local-name()='protocol'][@type='kubernetes.KUBE_PING']
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()="protocol"][@type="dns.DNS_PING"]
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()="protocol"][@type="openshift.KUBE_PING"]
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()="protocol"][@type="openshift.DNS_PING"]

  # https://issues.jboss.org/browse/CLOUD-1958
  Scenario: Check if dns ping protocol is used when specified
    When container is started with env
      | variable                             | value           |
      | JGROUPS_PING_PROTOCOL                | openshift.DNS_PING     |
    # 2 matches, one for TCP, one for UDP
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 2 elements on XPath //*[local-name()="protocol"][@type="dns.DNS_PING"]
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()="protocol"][@type="kubernetes.KUBE_PING"]
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()="protocol"][@type="openshift.KUBE_PING"]
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()="protocol"][@type="openshift.DNS_PING"]

    Scenario: Check if kube ping protocol is used when specified
    When container is started with env
      | variable                             | value           |
      | JGROUPS_PING_PROTOCOL                | kubernetes.KUBE_PING     |
    # 2 matches, one for TCP, one for UDP
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 2 elements on XPath //*[local-name()='protocol'][@type='kubernetes.KUBE_PING']
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()="protocol"][@type="dns.DNS_PING"]
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()="protocol"][@type="openshift.KUBE_PING"]
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()="protocol"][@type="openshift.DNS_PING"]

  Scenario: Check if dns ping protocol is used when specified
    When container is started with env
      | variable                             | value           |
      | JGROUPS_PING_PROTOCOL                | dns.DNS_PING    |
    # 2 matches, one for TCP, one for UDP
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 2 elements on XPath //*[local-name()="protocol"][@type="dns.DNS_PING"]
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()="protocol"][@type="kubernetes.KUBE_PING"]
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()="protocol"][@type="openshift.KUBE_PING"]
    Then XML file /opt/eap/standalone/configuration/standalone-openshift.xml should have 0 elements on XPath //*[local-name()="protocol"][@type="openshift.DNS_PING"]

  # CD doesn't have these any more, count should be 0
  Scenario: No duplicate module jars
    When container is ready
    Then file at /opt/eap/modules/system/layers/openshift/org/jgroups/main should not exist

  @wip
  Scenario: Run custom setup in image before launch
    When container is started with command bash
      Then run java -version in container and check its output for openjdk version "11.0.
      Then run ls -d /tmp in container and check its output contains /tmp
      Then run script -c /opt/eap/bin/openshift-launch.sh /tmp/boot.log in container and detach
      Then run ls -l /tmp in container and check its output contains boot.log
      Then file /tmp/boot.log should contain JGroups
      Then file /tmp/boot.log should not contain SHAZAM
