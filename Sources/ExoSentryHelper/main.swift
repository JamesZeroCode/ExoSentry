import Foundation

let service = HelperService(sleepController: SystemSleepSettingsController())
let listener = HelperXPCListener(service: service)
listener.run()
