import Foundation

final class AppLocalizer: ObservableObject {
  func text(_ key: String, _ arguments: CVarArg...) -> String {
    text(key, arguments: arguments)
  }

  func text(_ key: String, arguments: [CVarArg]) -> String {
    let format = NSLocalizedString(
      key,
      tableName: "Localizable",
      bundle: localizationBundle,
      value: key,
      comment: ""
    )

    guard !arguments.isEmpty else {
      return format
    }

    return String(
      format: format,
      locale: Locale(identifier: "en"),
      arguments: arguments
    )
  }

  private let localizationBundle: Bundle = {
    guard
      let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
      let bundle = Bundle(path: path)
    else {
      return .main
    }

    return bundle
  }()
}

indirect enum LocalizedMessage: Equatable {
  case key(String, [LocalizedMessage] = [])
  case coreAudioError(LocalizedMessage, OSStatus)
  case raw(String)

  func resolve(with localizer: AppLocalizer) -> String {
    switch self {
    case .key(let key, let arguments):
      let resolvedArguments: [CVarArg] = arguments.map { $0.resolve(with: localizer) as NSString }
      return localizer.text(key, arguments: resolvedArguments)
    case .coreAudioError(let context, let status):
      return localizer.text(
        "coreaudio.error %@ %lld",
        context.resolve(with: localizer),
        Int64(status)
      )
    case .raw(let text):
      return text
    }
  }
}
