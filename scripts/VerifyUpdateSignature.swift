import CryptoKit
import Foundation

func verifyUpdateSignature(arguments: [String]) throws {
  guard arguments.count == 4,
    let publicData = Data(base64Encoded: arguments[1]),
    let signature = Data(base64Encoded: arguments[3])
  else { throw VerificationFailure.invalidArguments }
  let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
  let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[2]), options: .mappedIfSafe)
  guard key.isValidSignature(signature, for: archive) else {
    throw VerificationFailure.invalidSignature
  }
}

enum VerificationFailure: Error { case invalidArguments, invalidSignature }

do { try verifyUpdateSignature(arguments: CommandLine.arguments) }
catch {
  fputs("Update signature verification failed: \(error)\n", stderr)
  exit(EXIT_FAILURE)
}
