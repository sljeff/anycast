//
//  SharedMediaTypes.swift
//  Share Extension
//
//  Vendored from receive_sharing_intent (KasemJaffer fork, ref 2cea3968)
//  ios/Classes/SwiftReceiveSharingIntentPlugin.swift — the extension only
//  needs these value types/constants; dropping the pod removes the
//  Flutter/Flutter.h module dependency that breaks extension builds on
//  newer Xcode (migration doc 08 §12.1-4, option "vendor the plugin").
//

import UniformTypeIdentifiers

public let kSchemePrefix = "ShareMedia"
public let kUserDefaultsKey = "ShareKey"
public let kUserDefaultsMessageKey = "ShareMessageKey"
public let kAppGroupIdKey = "AppGroupId"

public class SharedMediaFile: Codable {
    var path: String
    var mimeType: String?
    var thumbnail: String? // video thumbnail
    var duration: Double? // video duration in milliseconds
    var message: String? // post message
    var type: SharedMediaType


    public init(
        path: String,
        mimeType: String? = nil,
        thumbnail: String? = nil,
        duration: Double? = nil,
        message: String?=nil,
        type: SharedMediaType) {
            self.path = path
            self.mimeType = mimeType
            self.thumbnail = thumbnail
            self.duration = duration
            self.message = message
            self.type = type
        }
}

public enum SharedMediaType: String, Codable, CaseIterable {
    case image
    case video
    case text
//     case audio
    case file
    case url

    public var toUTTypeIdentifier: String {
        if #available(iOS 14.0, *) {
            switch self {
            case .image:
                return UTType.image.identifier
            case .video:
                return UTType.movie.identifier
            case .text:
                return UTType.text.identifier
    //         case .audio:
    //             return UTType.audio.identifier
            case .file:
                return UTType.fileURL.identifier
            case .url:
                return UTType.url.identifier
            }
        }
        switch self {
        case .image:
            return "public.image"
        case .video:
            return "public.movie"
        case .text:
            return "public.text"
//         case .audio:
//             return "public.audio"
        case .file:
            return "public.file-url"
        case .url:
            return "public.url"
        }
    }
}
