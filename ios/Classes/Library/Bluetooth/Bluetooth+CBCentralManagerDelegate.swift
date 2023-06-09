//
//  Bluetooth+CBCentralManagerDelegate.swift
//  ble_lib
//
//  Created by Doan Ho on 14/04/2023.
//

import Foundation
import CoreBluetooth

// MARK: - CBCentralManagerDelegate
@available(iOS 14.0, *)
extension Bluetooth: CBCentralManagerDelegate {
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        if filters.contains(where: { $0 == .connectable }) {
            if isConnectable ?? false {
                devicePublisher.send((peripheral, advertisementData, RSSI))
            }
        } else {
            devicePublisher.send((peripheral, advertisementData, RSSI))
        }
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.debug("[Callback] centralManagerDidUpdateState(central: \(central))")
        managerState = central.state
        logger.info("Bluetooth changed state: \(central.state)")
        
        if central.state != .poweredOn {
            shouldScan = false
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.debug("[Callback] centralManager(central: \(central), didConnect: \(peripheral))")
        dataStreams[peripheral.identifier.uuidString] = [AsyncThrowingStream<AsyncStreamValue, Error>.Continuation]()
        guard case .connection(let continuation)? = continuations[peripheral.identifier.uuidString] else { return }
        continuation.resume(returning: peripheral)
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.debug("[Callback] centralManager(central: \(central), didFailToConnect: \(peripheral), error: \(error.debugDescription))")
        // Can only happen when trying to connect.
        guard case .connection(let continuation)? = continuations[peripheral.identifier.uuidString] else { return }
        if let error = error {
            let rethrow = BluetoothError.failedToConnect(description: error.localizedDescription)
            continuation.resume(throwing: rethrow)
            reportDataStreamError(rethrow, for: peripheral)
        } else {
            // Success.
            continuation.resume(returning: peripheral)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.debug("[Callback] centralManager(central: \(central), didDisconnectPeripheral: \(peripheral), error: \(error.debugDescription))")
        if let error = error {
            // If there's a Connection Continuation, it's very likely this is a user-requested disconnection.
            // Otherwise it's unexpected and is likely 'an error'.
            guard case .connection(let continuation)? = continuations[peripheral.identifier.uuidString] else {
                let error = BluetoothError.unexpectedDeviceDisconnection(description: error.localizedDescription)
                reportContinuationError(error, for: peripheral)
                reportDataStreamError(error, for: peripheral)
                return
            }
            
            let error = BluetoothError(error)
            continuation.resume(throwing: error)
            reportDataStreamError(error, for: peripheral)
        } else {
            // Success.
            dataStreams[peripheral.identifier.uuidString]?.forEach {
                $0.finish()
            }
            dataStreams[peripheral.identifier.uuidString]?.removeAll()
            guard case .connection(let ccontinuation)? = continuations[peripheral.identifier.uuidString] else { return }
            ccontinuation.resume(returning: peripheral)
        }
    }
}
