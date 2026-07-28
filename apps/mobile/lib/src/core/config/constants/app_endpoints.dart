class AppEndpoints {
  // Uploads
  static const String uploadPresign = "/upload/presign"; // POST
  static const String uploadMultipartStart = "/upload/multipart/start"; // POST
  static const String uploadMultipartParts = "/upload/multipart/parts"; // POST
  static const String uploadMultipartListParts =
      "/upload/multipart/list-parts"; // POST
  static const String uploadMultipartComplete =
      "/upload/multipart/complete"; // POST
  static const String uploadMultipartFinalize =
      "/upload/multipart/finalize"; // POST (server-side auto-complete)
  static const String uploadMultipartAbort = "/upload/multipart/abort"; // POST

  // Assets
  static const String assets = "/assets"; // POST create, GET list

  // Account
  static const String usersMe = "/users/me"; // GET current user, DELETE account
  static const String deleteAccount = usersMe;
}
