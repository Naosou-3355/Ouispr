// OuisprCore/Sources/OuisprCore/Logger.swift
import os.log

/// Centralized loggers for Ouispr subsystems.
/// Usage: OuisprLogger.keyboard.debug("message")
@available(iOS 14.0, macOS 11.0, *)
public enum OuisprLogger {
    public static let app = Logger(subsystem: "com.pivi.dictus", category: "app")
    public static let keyboard = Logger(subsystem: "com.pivi.dictus", category: "keyboard")
    public static let appGroup = Logger(subsystem: "com.pivi.dictus", category: "appGroup")
}
