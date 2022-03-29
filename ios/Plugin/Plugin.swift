import Foundation
import Capacitor
import GoogleSignIn

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitor.ionicframework.com/docs/plugins/ios
 */
@objc(GoogleAuth)
public class GoogleAuth: CAPPlugin {
    private var signInCall: CAPPluginCall!
    private var googleSignIn = {
        return GIDSignIn.sharedInstance
    }()
    private var googleSignInConfiguration: GIDConfiguration!
    private var forceAuthCode: Bool = false
    private var additionalScopes: [String]!
    
    // these are scopes granted by default by the signIn method
    private let defaultGrantedScopes = ["email", "profile", "openid"];

    /// On plugin load, we want to load static configuration using capacitor.config.js
    /// In case you want to use dynamic configuration, you can override this values
    /// at `initialize` method call.
    public override func load() {
        guard let staticConfigClientId = self.getClientIdValue() else {
            NSLog("No client id found in config")
            return;
        }
                
        let staticConfigServerClientId = self.getConfigValue("serverClientId") as? String
        let staticConfigScopes = self.getConfigValue("scopes") as? [String] ?? []
        
        self.googleSignInConfiguration = GIDConfiguration.init(clientID: staticConfigClientId,
                                                               serverClientID: staticConfigServerClientId)
        self.additionalScopes = self.getAdditionalScopes(scopes: staticConfigScopes)
        self.forceAuthCode = self.getConfigValue("forceCodeForRefreshToken") as? Bool ?? false
                
        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenUrl(_ :)), name: Notification.Name(Notification.Name.capacitorOpenURL.rawValue), object: nil);
    }

    /// By passing options in the `initialize` call, you will override values that
    /// were loaded from static config. The existing values that do not overlap will
    /// remain unchanged. If both `clientId` and `iosClientId` are passed,
    /// `iosClientId` will be used.
    @objc
    func initialize(_ call: CAPPluginCall) {
        let scopes: [String] = call.getArray("scopes", String.self) ?? []
        let serverClientId: String? = call.getString("serverClientId")

        if let clientId: String = call.getString("clientId") {
            self.googleSignInConfiguration = GIDConfiguration.init(clientID: clientId,
                                                                   serverClientID: serverClientId)
        }
        // will override clientId if passed
        if let iosClientId: String = call.getString("iosClientId") {
            self.googleSignInConfiguration = GIDConfiguration.init(clientID: iosClientId,
                                                                   serverClientID: serverClientId)
        }
        
        self.forceAuthCode = call.getBool("forceCodeForRefreshToken") ?? false
        self.additionalScopes = self.getAdditionalScopes(scopes: scopes)
        call.resolve();
    }

    @objc
    func signIn(_ call: CAPPluginCall) {
        signInCall = call;
        DispatchQueue.main.async {
            if self.googleSignIn.hasPreviousSignIn() && !self.forceAuthCode {
                self.googleSignIn.restorePreviousSignIn() { user, error in
                if let error = error {
                    self.signInCall?.reject(error.localizedDescription);
                    return;
                }
                self.resolveSignInCallWith(user: user!)
                }
            } else {
                let presentingVc = self.bridge!.viewController!;
                
                self.googleSignIn.signIn(with: self.googleSignInConfiguration, presenting: presentingVc) { user, error in
                    if let error = error {
                        self.signInCall?.reject(error.localizedDescription, "\(error._code)");
                        return;
                    }
                    if self.additionalScopes.count > 0 {
                        // requesting additional scopes in GoogleSignIn-iOS SDK 6.0 requires that you sign the user in and then request additional scopes,
                        // there's no method to include the additional scopes in the initial sign in request
                        self.googleSignIn.addScopes(self.additionalScopes, presenting: presentingVc) { user, error in
                            if let error = error {
                                self.signInCall?.reject(error.localizedDescription);
                                return;
                            }
                            self.resolveSignInCallWith(user: user!);
                        }
                    } else {
                        self.resolveSignInCallWith(user: user!);
                    }
                };
            }
        }
    }

    @objc
    func refresh(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if self.googleSignIn.currentUser == nil {
                call.reject("User not logged in.");
                return
            }
            self.googleSignIn.currentUser!.authentication.do { (authentication, error) in
                guard let authentication = authentication else {
                    call.reject(error?.localizedDescription ?? "Something went wrong.");
                    return;
                }
                let authenticationData: [String: Any] = [
                    "accessToken": authentication.accessToken,
                    "idToken": authentication.idToken ?? NSNull(),
                    "refreshToken": authentication.refreshToken
                ]
                call.resolve(authenticationData);
            }
        }
    }

    @objc
    func signOut(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.googleSignIn.signOut();
        }
        call.resolve();
    }

    @objc
    func handleOpenUrl(_ notification: Notification) {
        guard let object = notification.object as? [String: Any] else {
            print("There is no object on handleOpenUrl");
            return;
        }
        guard let url = object["url"] as? URL else {
            print("There is no url on handleOpenUrl");
            return;
        }
        googleSignIn.handle(url);
    }
    
    
    func getClientIdValue() -> String? {
        if let clientId = getConfigValue("iosClientId") as? String {
            return clientId;
        }
        else if let clientId = getConfigValue("clientId") as? String {
            return clientId;
        }
        else if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
                let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject],
                let clientId = dict["CLIENT_ID"] as? String {
            return clientId;
        }
        return nil;
    }
    
    func getServerClientIdValue() -> String? {
        if let serverClientId = getConfigValue("serverClientId") as? String {
            return serverClientId;
        }
        return nil;
    }

    func resolveSignInCallWith(user: GIDGoogleUser) {
        var userData: [String: Any] = [
            "authentication": [
                "accessToken": user.authentication.accessToken,
                "idToken": user.authentication.idToken,
                "refreshToken": user.authentication.refreshToken
            ],
            "serverAuthCode": user.serverAuthCode ?? NSNull(),
            "email": user.profile?.email ?? NSNull(),
            "familyName": user.profile?.familyName ?? NSNull(),
            "givenName": user.profile?.givenName ?? NSNull(),
            "id": user.userID ?? NSNull(),
            "name": user.profile?.name ?? NSNull()
        ];
        if let imageUrl = user.profile?.imageURL(withDimension: 100)?.absoluteString {
            userData["imageUrl"] = imageUrl;
        }
        signInCall?.resolve(userData);
    }
    
    private func getAdditionalScopes(scopes: [String]) -> [String] {
        // these are scopes we will need to request after sign in
        additionalScopes = scopes.filter {
            return !defaultGrantedScopes.contains($0);
        };
        
        return additionalScopes
    }
}
