function getRequestOrigin(req) {
  const forwardedProto = req.headers["x-forwarded-proto"];
  const forwardedHost = req.headers["x-forwarded-host"];
  const proto = forwardedProto ? String(forwardedProto).split(",")[0].trim() : req.protocol;
  const host = forwardedHost ? String(forwardedHost).split(",")[0].trim() : req.get("host");

  if (!host) {
    return "";
  }

  return `${proto}://${host}`;
}

function getLegacyAdminUploadsOrigin() {
  return "https://doorshoppin.com/admin/uploads";
}

function extractFilenameFromPath(pathLike) {
  return String(pathLike || "")
    .split("/")
    .filter(Boolean)
    .pop()
    ?.split("?")[0] ?? "";
}

export function normalizeProductImageUrl(req, imageUrl) {
  if (!imageUrl) {
    return imageUrl;
  }

  if (/^https?:\/\//i.test(imageUrl)) {
    try {
      const parsedUrl = new URL(imageUrl);
      if (/^\/uploads\//i.test(parsedUrl.pathname)) {
        const filename = extractFilenameFromPath(parsedUrl.pathname);
        return `${getLegacyAdminUploadsOrigin()}/${filename}`;
      }
    } catch (_) {
      // Fall through to the original value if URL parsing fails.
    }
    return imageUrl;
  }

  const rawPath = imageUrl.startsWith("/") ? imageUrl : `/${imageUrl}`;
  const normalizedPath = rawPath.replace(/\/{2,}/g, "/");
  const origin = getRequestOrigin(req);

  if (normalizedPath.startsWith("/uploads/")) {
    const filename = extractFilenameFromPath(normalizedPath);
    return `${getLegacyAdminUploadsOrigin()}/${filename}`;
  }

  if (!imageUrl.includes("/") && !/^https?:\/\//i.test(imageUrl)) {
    return `${getLegacyAdminUploadsOrigin()}/${imageUrl}`;
  }

  if (!origin) {
    return normalizedPath;
  }

  return `${origin}${normalizedPath}`;
}

export function normalizeProduct(req, product) {
  if (!product) {
    return product;
  }

  return {
    ...product,
    imageUrl: normalizeProductImageUrl(req, product.imageUrl),
  };
}

export function normalizeProducts(req, products) {
  if (!Array.isArray(products)) {
    return [];
  }

  return products.map((product) => normalizeProduct(req, product));
}
