<?php
header('Content-Type: application/json');
http_response_code(410);

echo json_encode([
    'success' => false,
    'message' => 'Legacy PHP product upload is disabled. Use the authenticated Node API: POST /api/admin/upload, then POST /api/admin/products.'
]);
