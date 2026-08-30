route:
  receiver: discord
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 6h

receivers:
  - name: discord
    discord_configs:
      - webhook_url: "__DISCORD_WEBHOOK__"
        title: "[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}"
        message: "{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}"
