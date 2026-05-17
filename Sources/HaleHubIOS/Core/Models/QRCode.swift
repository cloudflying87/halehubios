import Foundation

struct QRCode: Identifiable, Codable, Sendable {
    let id: String          // UUID string from server
    let name: String
    let qrType: String      // "text"|"url"|"wifi"|"email"|"phone"|"sms"
    let isDynamic: Bool
    let shortCode: String
    let qrImageUrl: String? // absolute URL to PNG
    let scanCount: Int
    let isActive: Bool
    let createdAt: Date
    var contentData: QRContentData
}

// content_data is a freeform JSON dict — each type uses a subset of these fields
struct QRContentData: Codable, Sendable {
    // URL type
    var url: String?
    // Text type
    var text: String?
    // WiFi type
    var ssid: String?
    var password: String?
    var security: String?   // "WPA"|"WEP"|"nopass"
    var hidden: Bool?
    // Email type
    var email: String?
    var subject: String?
    var body: String?
    // Phone type
    var phone: String?
    // SMS type — also reuses phone
    var message: String?
}

struct CreateQRCodeRequest: Encodable, Sendable {
    let name: String
    let qrType: String
    let isDynamic: Bool
    let contentData: QRContentData
}
