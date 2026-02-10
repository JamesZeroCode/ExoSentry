import Foundation

final class HelperXPCListener: NSObject, NSXPCListenerDelegate {
    private let service: HelperService
    private let listener: NSXPCListener

    init(
        service: HelperService,
        machServiceName: String = "com.exosentry.helper"
    ) {
        self.service = service
        self.listener = NSXPCListener(machServiceName: machServiceName)
        super.init()
        listener.delegate = self
    }

    func run() {
        listener.resume()
        RunLoop.current.run()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: ExoSentryHelperXPCProtocol.self)
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}
