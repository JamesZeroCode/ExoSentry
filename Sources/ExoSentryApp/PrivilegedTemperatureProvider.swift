import ExoSentryCore
import ExoSentryXPC

struct PrivilegedTemperatureProvider: TemperatureProviding {
    private let client: PrivilegedCommanding

    init(client: PrivilegedCommanding) {
        self.client = client
    }

    func currentTemperatureC() -> Double? {
        client.currentSOCTemperature()
    }
}
