import ExoSentryCore
import SwiftUI

extension GuardStatus {
    var displayName: String {
        switch self {
        case .active: return "守护中"
        case .paused: return "已暂停"
        case .degraded: return "已降级"
        case .overheatTrip: return "过热熔断"
        }
    }

    var statusColor: Color {
        switch self {
        case .active: return ExoSentryTheme.statusActive
        case .paused: return ExoSentryTheme.statusPaused
        case .degraded: return ExoSentryTheme.statusDegraded
        case .overheatTrip: return ExoSentryTheme.statusOverheat
        }
    }

    var iconName: String {
        switch self {
        case .active: return "circle.fill"
        case .paused: return "circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .overheatTrip: return "flame.fill"
        }
    }
}

extension OperatingMode {
    var displayName: String {
        switch self {
        case .cluster: return "集群"
        case .standard: return "标准"
        }
    }
}

extension NetworkState {
    var displayName: String {
        switch self {
        case .ok: return "正常"
        case .lanLost: return "局域网断开"
        case .wanLost: return "外网断开"
        case .offline: return "离线"
        }
    }
}
