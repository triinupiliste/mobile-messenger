/// Extracts a user id from either key spelling (`userId` from socket payloads
/// vs `user_id`/`id` from the REST API), returning null if neither is present.
String? extractUserId(Map<String, dynamic> json, [String primaryKey = 'id']) {
  return json[primaryKey]?.toString() ?? json['user_id']?.toString();
}
