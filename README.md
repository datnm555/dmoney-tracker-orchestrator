# dmoney-tracker-orchestrator

Chạy toàn bộ dmoney-tracker (postgres + api + web) — yêu cầu 2 repo anh em nằm cạnh:

```
dmoney/
├── dmoney-tracker-be/
├── dmoney-tracker-web/
└── dmoney-tracker-orchestrator/   ← chạy lệnh từ đây
```

```bash
docker compose up --build
```

Web: http://localhost:8080 — API: http://localhost:5113. Khi deploy thật, override
`Jwt__Secret`, `Cors__Origins`, `ConnectionStrings__Database` qua biến môi trường.
