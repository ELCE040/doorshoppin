// cPanel/Passenger-compatible bootstrap for ESM server
// Set this file as "Application startup file" in cPanel.
process.on("unhandledRejection", (err) => {
  console.error("Startup unhandledRejection:", err);
});

process.on("uncaughtException", (err) => {
  console.error("Startup uncaughtException:", err);
});

import("./server.js").catch((err) => {
  console.error("Failed to import server.js:", err);
  process.exit(1);
});

