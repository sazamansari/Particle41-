const express = require("express");
const os = require("os");

const app = express();
const PORT = 3000;

app.get("/", (req, res) => {
  res.json({
    timestamp: new Date().toISOString(),
    ip: req.headers["x-forwarded-for"] || req.socket.remoteAddress
  });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});