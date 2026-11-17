import XCTest
@testable import Prizm

/// PIN wrapping uses the real KDF and authenticated encryption; storage and networking are in memory.
@MainActor
final class AuthRepositoryPINTests: XCTestCase {
    private var sut: AuthRepositoryImpl!
    private var crypto: PrizmCryptoServiceImpl!
    private var keychain: MockKeychainService!
    private var api: MockPrizmAPIClient!
    private var biometrics: MockBiometricKeychainService!

    private let userId = "pin-user"
    private let email = "pin@example.com"
    private let pin = Data("683921".utf8)
    private let password = Data("test master password".utf8)
    private let vaultKeys = CryptoKeys(
        encryptionKey: Data(repeating: 0x31, count: 32),
        macKey: Data(repeating: 0x72, count: 32)
    )

    override func setUp() async throws {
        crypto = PrizmCryptoServiceImpl()
        keychain = MockKeychainService()
        api = MockPrizmAPIClient()
        biometrics = MockBiometricKeychainService()
        sut = makeRepository()
        let environment = ServerEnvironment(base: URL(string: "https://vault.example.com")!, overrides: nil)
        let kdf = KdfParams(type: .pbkdf2, iterations: 10_000, memory: nil, parallelism: nil)
        let masterKey = try await crypto.makeMasterKey(password: password, email: email, kdf: kdf)
        let stretched = try await crypto.stretchKey(masterKey: masterKey)
        let encryptedVaultKey = try EncString.encrypt(data: vaultKeys.toData(), keys: stretched).toString()
        keychain.seed(key: KeychainKey.activeUserId, value: userId)
        keychain.seed(key: KeychainKey.user(userId, "email"), value: email)
        keychain.seed(key: KeychainKey.user(userId, "serverEnvironment"), data: try JSONEncoder().encode(environment))
        keychain.seed(key: KeychainKey.user(userId, "kdfParams"), data: try JSONEncoder().encode(kdf))
        keychain.seed(key: KeychainKey.user(userId, "encUserKey"), value: encryptedVaultKey)
        keychain.seed(key: KeychainKey.user(userId, "accessToken"), value: "test-token")
        await crypto.unlockWith(keys: vaultKeys)
    }

    func testPINUnlock_restoresExactKeysAndAccountAfterLock() async throws {
        try await sut.enablePINUnlock(pin)
        await sut.lockVault()
        let account = try await sut.unlockWithPIN(pin)
        let restoredKeys = try await crypto.currentKeys()
        XCTAssertEqual(account.userId, userId)
        XCTAssertEqual(restoredKeys.toData(), vaultKeys.toData())
    }

    func testWrongPIN_doesNotUnlock() async throws {
        try await sut.enablePINUnlock(pin)
        await sut.lockVault()
        do {
            _ = try await sut.unlockWithPIN(Data("000000".utf8))
            XCTFail("Wrong PIN must not unlock")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidPIN)
        }
        let unlocked = await crypto.isUnlocked
        XCTAssertFalse(unlocked)
    }

    func testFiveWrongPINs_requirePasswordAndPreserveConfiguration() async throws {
        try await sut.enablePINUnlock(pin)
        await sut.lockVault()
        for attempt in 1...5 {
            do {
                _ = try await sut.unlockWithPIN(Data("000000".utf8))
                XCTFail("Wrong PIN must not unlock")
            } catch {
                XCTAssertEqual(error as? AuthError, attempt == 5 ? .pinAttemptsExceeded : .invalidPIN)
            }
        }
        XCTAssertFalse(sut.pinUnlockAvailable)
        XCTAssertTrue(sut.pinUnlockEnabled)
        _ = try await sut.unlockWithPassword(password)
        XCTAssertTrue(sut.pinUnlockAvailable)
        await sut.lockVault()
        _ = try await sut.unlockWithPIN(pin)
    }

    func testNewRepository_requiresPasswordBeforePINWorksAgain() async throws {
        try await sut.enablePINUnlock(pin)
        await sut.lockVault()
        sut = makeRepository()
        XCTAssertTrue(sut.pinUnlockEnabled)
        XCTAssertFalse(sut.pinUnlockAvailable)
        do {
            _ = try await sut.unlockWithPIN(pin)
            XCTFail("A restarted app must require the master password first")
        } catch {
            XCTAssertEqual(error as? AuthError, .pinUnavailable)
        }
        _ = try await sut.unlockWithPassword(password)
        XCTAssertTrue(sut.pinUnlockAvailable)
        await sut.lockVault()
        _ = try await sut.unlockWithPIN(pin)
    }

    func testBiometricUnlockAfterRestart_doesNotArmPIN() async throws {
        try await sut.enablePINUnlock(pin)
        try biometrics.writeBiometric(data: vaultKeys.toData(), key: KeychainKey.biometricVaultKey(userId))
        await sut.lockVault()
        sut = makeRepository()
        _ = try await sut.unlockWithBiometrics()
        XCTAssertTrue(sut.pinUnlockEnabled)
        XCTAssertFalse(sut.pinUnlockAvailable)
    }

    func testEnablePIN_rejectsLockedVaultAndInvalidFormat() async throws {
        for value in ["12345", "1234567890123", "12a456", "１２３４５６"] {
            do {
                try await sut.enablePINUnlock(Data(value.utf8))
                XCTFail("Only 6–12 ASCII digits are accepted")
            } catch {
                XCTAssertEqual(error as? AuthError, .invalidPINFormat)
            }
        }
        await sut.lockVault()
        do {
            try await sut.enablePINUnlock(pin)
            XCTFail("Cannot configure PIN with a locked vault")
        } catch {
            XCTAssertEqual(error as? AuthError, .pinUnavailable)
        }
    }

    func testPersistedPINRecord_cannotBeDecryptedWithPIN() async throws {
        try await sut.enablePINUnlock(pin)
        let data = try keychain.read(key: KeychainKey.user(userId, "pinUnlock"))
        let record = try JSONDecoder().decode(PersistedRecord.self, from: data)
        let kdf = KdfParams(type: .pbkdf2, iterations: 600_000, memory: nil, parallelism: nil)
        let masterKey = try await crypto.makeMasterKey(password: pin, email: record.salt, kdf: kdf)
        let pinKeys = try await crypto.stretchKey(masterKey: masterKey)
        let encryptedPINKey = try EncString(string: record.encryptedPINKey)
        XCTAssertThrowsError(try encryptedPINKey.decrypt(keys: pinKeys))
        XCTAssertEqual(try encryptedPINKey.decrypt(keys: vaultKeys), pinKeys.toData())
    }

    func testDisableAndSignOut_removePINConfiguration() async throws {
        try await sut.enablePINUnlock(pin)
        try await sut.disablePINUnlock()
        XCTAssertFalse(sut.pinUnlockEnabled)
        XCTAssertFalse(sut.pinUnlockAvailable)
        try await sut.enablePINUnlock(pin)
        try await sut.signOut()
        XCTAssertFalse(sut.pinUnlockEnabled)
        XCTAssertFalse(sut.pinUnlockAvailable)
        XCTAssertThrowsError(try keychain.read(key: KeychainKey.user(userId, "pinUnlock")))
    }

    private func makeRepository() -> AuthRepositoryImpl {
        AuthRepositoryImpl(apiClient: api, crypto: crypto, keychain: keychain, biometricKeychain: biometrics)
    }

    private struct PersistedRecord: Decodable {
        let salt: String
        let encryptedPINKey: String
    }
}
