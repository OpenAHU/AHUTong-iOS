import Foundation

/// A failed OCR result is a failed challenge, not a rejected password. Each
/// retry fetches a fresh image and carries the school's rotated session cookie.
struct CampusCardLoginFlow: Sendable {
    private let captchaClient: CampusCardCaptchaClient
    private let recognizer: any CampusCaptchaRecognizing
    private let loginClient: CampusCardLoginClient

    init(captchaClient: CampusCardCaptchaClient = .init(),
         recognizer: any CampusCaptchaRecognizing = RemoteCampusCaptchaRecognizer(),
         loginClient: CampusCardLoginClient = .init()) {
        self.captchaClient = captchaClient
        self.recognizer = recognizer
        self.loginClient = loginClient
    }

    func login(credentials: LoginCredentials, cookies: [CampusCookie]) async throws -> [CampusCookie] {
        var cookies = cookies
        // Match Android's bounded challenge attempts. Network errors and
        // credential rejection stop immediately instead of repeating logins.
        for attempt in 0..<5 {
            try Task.checkCancellation()
            let image: CampusCardCaptchaImage
            do { image = try await captchaClient.fetch(cookies: cookies) }
            catch is CancellationError { throw CancellationError() }
            catch let error as CampusCardCaptchaFetchError {
                throw CampusWebAuthenticationError.campusCardCaptchaRequestFailed(error)
            }
            cookies = image.cookies
            let code: String
            do { code = try await recognizer.recognize(image.data) }
            catch CampusCaptchaRecognitionError.invalidCode where attempt < 4 { continue }
            catch is CancellationError { throw CancellationError() }
            catch let error as CampusCaptchaRecognitionError {
                throw CampusWebAuthenticationError.campusCardOCRFailed(error)
            }
            try Task.checkCancellation()
            do { return try await loginClient.login(credentials: credentials, captcha: code, cookies: cookies) }
            catch is CancellationError { throw CancellationError() }
            catch CampusCardLoginError.missingSchoolSession {
                throw CampusWebAuthenticationError.campusCardSchoolSessionMissing
            } catch CampusCardLoginError.invalidCaptcha {
                if attempt < 4 { continue }
                throw CampusWebAuthenticationError.campusCardOCRFailed(.invalidCode)
            } catch CampusCardLoginError.invalidResponse {
                throw CampusWebAuthenticationError.campusCardLoginResponseInvalid
            } catch CampusCardLoginError.credentialsRejected {
                throw CampusWebAuthenticationError.campusCardSchoolRejected
            } catch CampusCardLoginError.rejected(let message) {
                if message.contains("验证码") {
                    if attempt < 4 { continue }
                    throw CampusWebAuthenticationError.campusCardCaptchaRejected
                }
                throw CampusWebAuthenticationError.campusCardSchoolRejected
            }
        }
        throw CampusWebAuthenticationError.campusCardCaptchaRejected
    }
}
