# Grafana ClickHouse datasource — managed by scripts/provision-grafana.sh
# __CLICKHOUSE_HOST__ is substituted with the ClickHouse EC2 private IP at provision time.
# Protocol is HTTP (port 8123) to match the security group rule.
apiVersion: 1
datasources:
  - name: ClickHouse
    type: grafana-clickhouse-datasource
    isDefault: true
    jsonData:
      host: __CLICKHOUSE_HOST__
      port: 8123
      protocol: http
      defaultDatabase: aiops
      username: default
    editable: true
