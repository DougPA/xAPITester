//
//  Vita.swift
//  CommonCode
//
//  Created by Douglas Adams on 5/9/17.
//  Copyright © 2018 Douglas Adams & Mario Illgen. All rights reserved.
//

import Foundation

// --------------------------------------------------------------------------------
// MARK: - VitaHandler protocol
//
// --------------------------------------------------------------------------------

protocol VitaHandler {
  
  func vitaHandler(_ vitaPacket: Vita) -> Void
}

// ------------------------------------------------------------------------------
// MARK: - VITA header struct implementation
//
//      provides decoding and encoding services for Vita encoding
//      see http://www.vita.com
//
// ------------------------------------------------------------------------------

public struct VitaHeader {
  
  // this struct mirrors the structure of a Vita Header
  //      some of these fields are optional in a generic Vita-49 header
  //      however they are always present in the Flex usage of Vita-49
  //
  //      all of the UInt16 & UInt32 fields must be BigEndian
  //
  var packetDesc                      : UInt8 = 0
  var timeStampDesc                   : UInt8 = 0                           // the lsb four bits are used for sequence number
  var packetSize                      : UInt16 = 0
  var streamId                        : UInt32 = 0
  var oui                             : UInt32 = 0
  var classCodes                      : UInt32 = 0
  var integerTimeStamp                : UInt32 = 0
  var fractionalTimeStampMsb          : UInt32 = 0
  var fractionalTimeStampLsb          : UInt32 = 0
}

// ------------------------------------------------------------------------------
// MARK: - VITA class implementation
// ------------------------------------------------------------------------------

public class Vita {
  
  // this struct includes, in a more readily inspectable form, all of the properties
  // needed to populate a Vita Data packet. The "encode" instance method converts this
  // struct into a Vita Data packet. The "decode" static method converts a supplied
  // Vita Data packet into a Vita struct.
  
  // ----------------------------------------------------------------------------
  // MARK: - Internal properties
  
  // filled with defaults, values are changed when created
  //      Types are shown for clarity
  
  var packetType                      : PacketType = .extDataWithStream     // Packet type
  var classCode                       : PacketClassCode = .panadapter       // Packet class code
  var streamId                        : UInt32 = 0                          // Stream ID
  
  var classIdPresent                  : Bool = true                         // Class ID present
  var trailerPresent                  : Bool = false                        // Trailer present
  var tsiType                         : TsiType = .utc                      // Integer timestamp type
  var tsfType                         : TsfType = .sampleCount              // Fractional timestamp type
  var sequence                        : Int = 0                             // Mod 16 packet sequence number
  var packetSize                      : Int = 0                             // Size of packet (bytes)
  var integerTimestamp                : UInt32 = 0                          // Integer portion
  var fracTimeStampMsb                : UInt32 = 0                          // fractional portion - MSB 32 bits
  var fracTimeStampLsb                : UInt32 = 0                          // fractional portion -LSB 32 bits
  var oui                             : UInt32 = kFlexOui                   // Flex Radio oui
  var informationClassCode            : UInt32 = kFlexInformationClassCode  // Flex Radio classCode
  var payload                         : UnsafeRawPointer? = nil             // Void Pointer to the payload
  var payloadSize                     : Int = 0                             // Size of payload (bytes)
  var trailer                         : UInt32 = 0                          // Trailer, 4 bytes (if used)
  var headerSize                      : Int = MemoryLayout<VitaHeader>.size // Header size (bytes)
  
  /// Initialize this Vita struct with the defaults above
  ///
  init() {
    // nothing needed, all values are defaulted
  }
  
  /// Initialize a Vita struct as a dataWithStream (Ext or If)
  ///
  /// - Parameters:
  ///   - packetType:     a Vita Packet Type (.extDataWithStream || .ifDataWithStream)
  ///   - classCode:      a Vita Class Code
  ///   - streamId:       a Stream ID (as a String, no "0x")
  /// - Returns:          a partially populated Vita struct
  ///
  init(packetType: PacketType, classCode: PacketClassCode, streamId: UInt32, tsi: TsiType = .utc, tsf: TsfType = .sampleCount) {
    
    assert(packetType == .extDataWithStream || packetType == .ifDataWithStream)
    
    self.packetType = packetType
    self.classCode = classCode
    self.streamId = streamId
    self.tsiType = tsi
    self.tsfType = tsf
    
    // default values for:  HeaderSize, Oui, InformationClassCode, TimeStamp(s), Sequence,
    //                      PacketSize, Payload, PayloadSize, Trailer
    
    // to be changed later: TimeStamps, Sequence, PacketSize, Payload, PayloadSize, Trailer
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Class methods

  /// Create a Data type containing a Vita Discovery stream
  ///
  /// - Parameter payload:        the Discovery payload (as an array of String)
  /// - Returns:                  a Data type containing a Vita Discovery stream
  ///
  public class func discovery(payload: [String]) -> Data? {
    let kDiscoveryStreamId: UInt32 = 0x00000800
    
    // create a new Vita class (w/defaults & extDataWithStream / Discovery)
    let vita = Vita(packetType: .extDataWithStream, classCode: .discovery, streamId: kDiscoveryStreamId)
    
    // concatenate the strings, separated by space
    let payloadString = payload.joined(separator: " ")
    
    // calculate the actual length of the payload (in bytes)
    vita.payloadSize = payloadString.lengthOfBytes(using: .ascii)
    
    //        // calculate the number of UInt32 that can contain the payload bytes
    //        let payloadWords = Int((Float(vita.payloadSize) / Float(MemoryLayout<UInt32>.size)).rounded(.awayFromZero))
    //        let payloadBytes = payloadWords * MemoryLayout<UInt32>.size
    
    // create the payload array at the appropriate size (always a multiple of UInt32 size)
    var payloadArray = [UInt8](repeating: 0x20, count: vita.payloadSize)
    
    // packet size is Header + Payload (no Trailer)
    vita.packetSize = vita.payloadSize + MemoryLayout<VitaHeader>.size
    
    // convert the payload to an array of UInt8
    let cString = payloadString.cString(using: .ascii)!
    for i in 0..<cString.count - 1 {
      payloadArray[i] = UInt8(cString[i])
    }
    // give the Vita struct a pointer to the payload
    vita.payload = UnsafeRawPointer(payloadArray)
    
    // return the encoded Vita class as Data
    return Vita.encodeAsData(vita)
  }
  /// Decode a Data type into a Vita class
  ///
  /// - Parameter data:         a Data type containing a Vita stream
  /// - Returns:                a Vita class
  ///
  public class func decodeFrom(data: Data) -> Vita? {
    
    let kVitaMinimumBytes = 28          // Minimum size of a Vita packet (bytes)
    let kPacketTypeMask: UInt8 = 0xf0   // Bit masks
    let kClassIdPresentMask: UInt8 = 0x08
    let kTrailerPresentMask: UInt8 = 0x04
    let kTsiTypeMask: UInt8 = 0xc0
    let kTsfTypeMask: UInt8 = 0x30
    let kPacketSequenceMask: UInt8 = 0x0f
    let kInformationClassCodeMask: UInt32 = 0xffff0000
    let kPacketClassCodeMask: UInt32 = 0x0000ffff
    let kOffsetOptionals = 4            // byte offset to optional header section
    let kTrailerSize = 4                // Size of a trailer (bytes)
    
    var headerCount = 0
    
    let vita = Vita()
    
    // packet too short - return
    if data.count < kVitaMinimumBytes { return nil }
    
    // map the packet to the VitaHeader struct
    let vitaHeader = (data as NSData).bytes.bindMemory(to: VitaHeader.self, capacity: 1)
    
    // capture Packet Type
    guard let pt = PacketType(rawValue: (vitaHeader.pointee.packetDesc & kPacketTypeMask) >> 4) else {
      return nil
    }
    vita.packetType = pt
    
    // capture ClassId & TrailerId present
    vita.classIdPresent = (vitaHeader.pointee.packetDesc & kClassIdPresentMask) == kClassIdPresentMask
    vita.trailerPresent = (vitaHeader.pointee.packetDesc & kTrailerPresentMask) == kTrailerPresentMask
    
    // capture Time Stamp Integer
    guard let intStamp = TsiType(rawValue: (vitaHeader.pointee.timeStampDesc & kTsiTypeMask) >> 6) else {
      return nil
    }
    vita.tsiType = intStamp
    
    // capture Time Stamp Fractional
    guard let fracStamp = TsfType(rawValue: (vitaHeader.pointee.timeStampDesc & kTsfTypeMask) >> 4) else {
      return nil
    }
    vita.tsfType = fracStamp
    
    // capture PacketCount & PacketSize
    vita.sequence = Int((vitaHeader.pointee.timeStampDesc & kPacketSequenceMask))
    vita.packetSize = Int(CFSwapInt16BigToHost(vitaHeader.pointee.packetSize)) * 4
    
    // create an UnsafePointer<UInt32> to the optional words of the packet
    let vitaOptionals = (data as NSData).bytes.advanced(by: kOffsetOptionals).bindMemory(to: UInt32.self, capacity: 6)
    
    // capture Stream Id (if any)
    if vita.packetType == .ifDataWithStream || vita.packetType == .extDataWithStream {
      vita.streamId = CFSwapInt32BigToHost(vitaOptionals.pointee)
      
      // Increment past this item
      headerCount += 1
    }
    
    // capture Oui, InformationClass code & PacketClass code (if any)
    if vita.classIdPresent == true {
      vita.oui = CFSwapInt32BigToHost(vitaOptionals.advanced(by: headerCount).pointee) & kOuiMask
      
      let value = CFSwapInt32BigToHost(vitaOptionals.advanced(by: headerCount + 1).pointee)
      vita.informationClassCode = (value & kInformationClassCodeMask) >> 16
      
      guard let cc = PacketClassCode(rawValue: UInt16(value & kPacketClassCodeMask)) else {
        return nil
      }
      vita.classCode = cc
      
      // Increment past these items
      headerCount += 2
    }
    
    // capture the Integer Time Stamp (if any)
    if vita.tsiType != .none {
      // Integer Time Stamp present
      vita.integerTimestamp = CFSwapInt32BigToHost(vitaOptionals.advanced(by: headerCount).pointee)
      
      // Increment past this item
      headerCount += 1
    }
    
    // capture the Fractional Time Stamp (if any)
    if vita.tsfType != .none {
      // Fractional Time Stamp present
      vita.fracTimeStampMsb = CFSwapInt32BigToHost(vitaOptionals.advanced(by: headerCount).pointee)
      vita.fracTimeStampLsb = CFSwapInt32BigToHost(vitaOptionals.advanced(by: headerCount + 1).pointee)
      
      // Increment past these items
      headerCount += 2
    }
    
    // calculate the Header size (bytes)
    vita.headerSize = ( 4 * (headerCount + 1) )
    // calculate the payload size (bytes)
    // NOTE: The data payload size is NOT necessarily a multiple of 4 bytes (it can be any number of bytes)
    vita.payloadSize = data.count - vita.headerSize - (vita.trailerPresent ? kTrailerSize : 0)
    
    // get a <Void> pointer to the Payload
    vita.payload = UnsafeRawPointer((data as NSData).bytes.advanced(by: vita.headerSize))
    
    // capture the Trailer (if any)
    if vita.trailerPresent {
      // calculate the pointer to the Trailer (must be the last 4 bytes of the packet)
      let vitaTrailer = (data as NSData).bytes.advanced(by: data.count - 4).bindMemory(to: UInt32.self, capacity: 1)
      
      // capture the Trailer
      vita.trailer = CFSwapInt32BigToHost(vitaTrailer.pointee)
    }
    return vita
  }
  /// Encode a Vita class as a Data type
  ///
  /// - Returns:          a Data type containing the Vita stream
  ///
  public class func encodeAsData(_ vita: Vita) -> Data? {
    
    // TODO: Handle optional fields
    
    // create a Header struct
    var header = VitaHeader()
    
    // populate the header fields from the Vita struct
    
    // packet type
    header.packetDesc = (vita.packetType.rawValue & 0x0f) << 4
    
    // class id & trailer flags
    if vita.classIdPresent { header.packetDesc |= Vita.kClassIdPresentMask }
    if vita.trailerPresent { header.packetDesc |= Vita.kTrailerPresentMask }
    
    // time stamps
    header.timeStampDesc = ((vita.tsiType.rawValue & 0x03) << 6) | ((vita.tsfType.rawValue & 0x03) << 4)
    
    header.integerTimeStamp = CFSwapInt32HostToBig(vita.integerTimestamp)
    header.fractionalTimeStampLsb = CFSwapInt32HostToBig(vita.fracTimeStampLsb)
    header.fractionalTimeStampMsb = CFSwapInt32HostToBig(vita.fracTimeStampMsb)
    
    // sequence number
    header.timeStampDesc |= (UInt8(vita.sequence) & 0x0f)
    
    // oui
    header.oui = CFSwapInt32HostToBig(Vita.kFlexOui & Vita.kOuiMask)
    
    // class codes
    let classCodes = UInt32(vita.informationClassCode << 16) | UInt32(vita.classCode.rawValue)
    header.classCodes = CFSwapInt32HostToBig(classCodes)
    
    // packet size
    header.packetSize = CFSwapInt16HostToBig( UInt16(vita.packetSize/MemoryLayout<UInt32>.size) )
    
    // stream id
    header.streamId = CFSwapInt32HostToBig(vita.streamId)
    
    // create the Data type and populate it with the VitaHeader
    var data = Data(bytes: &header, count: MemoryLayout<VitaHeader>.size)
    
    // obtain a pointer to the bytes in the payload
    guard let uint8Ptr = vita.payload?.bindMemory(to: UInt8.self, capacity: vita.payloadSize) else {
      // Invalid payload pointer
      return nil
    }
    // append the payload bytes to the Data type
    //      assumes the payload data is already in big-endian form
    data.append(uint8Ptr, count: vita.payloadSize)
    
    // TODO: Handle Trailer data
    
    // return the Data type
    return data
  }
  /// Parse a Vita class containing a Discovery broadcast
  ///
  /// - Returns:        a RadioParameters struct (or nil)
  ///
  public class func parseDiscovery(_ vita: Vita) -> RadioParameters? {
    
    // is this a Discovery packet?
    if vita.classIdPresent && vita.classCode == .discovery {
      
      // YES, create a minimal RadioParameters with now as "lastSeen"
      let radio = RadioParameters()
      
      // Payload is a series of strings of the form <key=value> separated by ' ' (space)
      let payloadData = NSString(bytes: vita.payload!, length: vita.payloadSize, encoding: String.Encoding.ascii.rawValue)! as String
      
      // parse into a KeyValuesArray
      let keyValues = payloadData.keyValuesArray()
      
      // process each key/value pair, <key=value>
      for kv in keyValues {
        
        // check for unknown keys
        guard let token = DiscoveryToken(rawValue: kv.key) else {
          
          // unknown Key, log it and ignore the Key
          Api.sharedInstance.log.msg("Unknown token - \(kv.key)", level: .warning, function: #function, file: #file, line: #line)
          continue
        }
        
        switch token {
          
        case .callsign:
          radio.callsign = kv.value
          
        case .fpcMac:
          radio.fpcMac = kv.value
          
        case .inUseHost:
          radio.inUseHost = kv.value
          
        case .inUseIp:
          radio.inUseIp = kv.value
          
        case .ipAddress:
          radio.ipAddress = kv.value
          
        case .maxLicensedVersion:
          radio.maxLicensedVersion = kv.value
          
        case .model:
          radio.model = kv.value
          
        case .name:
          radio.name = kv.value
          
        case .nickname:
          radio.nickname = kv.value
          
        case .port:
          radio.port = kv.value.iValue()
          
        case .protocolVersion:
          radio.protocolVersion = kv.value
          
        case .radioLicenseId:
          radio.radioLicenseId = kv.value
          
        case .requiresAdditionalLicense:
          radio.requiresAdditionalLicense = kv.value
          
        case .serialNumber:
          radio.serialNumber = kv.value
          
        case .status:
          radio.status = kv.value
          
        case .firmwareVersion:
          radio.firmwareVersion = kv.value
          
        // satisfy the switch statement, not a real token
        case .lastSeen:
          break
        }
      }
      // is it a valid Discovery packet?
      if radio.ipAddress != "" && radio.port != 0 && radio.model != "" && radio.serialNumber != "" {
        // YES
        return radio
      }
    }
    // Not a Discovery packet
    return nil
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Instance methods
  
  /// Return a String description of a Vita class
  ///
  /// - Returns:          a String describing the Vita class
  ///
  public func desc() -> String {
    
    let payloadString = NSString(bytes: payload!, length: payloadSize, encoding: String.Encoding.ascii.rawValue)! as String
    
    return packetType.description() + "\n" +
      "classIdPresent = \(classIdPresent)\n" +
      "trailerPresent = \(trailerPresent)\n" +
      "tsi = \(tsiType.description())\n" +
      "tsf = \(tsfType.description())\n" +
      "sequence = \(sequence)\n" +
      "integerTimeStamp = \(integerTimestamp)\n" +
      "fracTimeStampMsb = \(fracTimeStampMsb)\n" +
      "fracTimeStampLsb = \(fracTimeStampLsb)\n" +
      "oui = \(String(format: "0x%x", oui))\n" +
      "informationClassCode = \(String(format: "0x%x", informationClassCode))\n" +
      "classCode = \(String(format: "0x%x", classCode.rawValue))\n" +
      "trailer = \(trailer)\n" +
      "streamId = 0x\(streamId)\n" +
      "headerSize = \(headerSize) bytes\n" +
      "payloadSize = \(payloadSize) bytes\n" +
      "packetSize = \(packetSize) bytes\n" +
    payloadString
  }
}

// --------------------------------------------------------------------------------
// MARK: - Vita Class extensions
//              - Static properties
//              - DiscoveryToken enum
//              - Vita Packet enums
// --------------------------------------------------------------------------------

extension Vita {
  
  // Flex specific codes
  static let kFlexOui                       : UInt32 = 0x1c2d
  static let kOuiMask                       : UInt32 = 0x00ffffff
  static let kFlexInformationClassCode      : UInt32 = 0x534c
  static let kClassIdPresentMask            : UInt8 = 0x08
  static let kTrailerPresentMask            : UInt8 = 0x04
  
  enum DiscoveryToken : String {            // Discovery Tokens
    case callsign
    case fpcMac                             = "fpc_mac"
    case inUseHost                          = "inuse_host"
    case inUseIp                            = "inuse_ip"
    case ipAddress                          = "ip"
    case maxLicensedVersion                 = "max_licensed_version"
    case model
    case name
    case nickname
    case port
    case protocolVersion                    = "discovery_protocol_version"
    case radioLicenseId                     = "radio_license_id"
    case requiresAdditionalLicense          = "requires_additional_license"
    case serialNumber                       = "serial"
    case status
    case firmwareVersion                    = "version"
    
    case lastSeen   // not a real token
  }
  public enum PacketType : UInt8 {          // Packet Types
    case ifData                             = 0x00
    case ifDataWithStream                   = 0x01
    case extData                            = 0x02
    case extDataWithStream                  = 0x03
    case ifContext                          = 0x04
    case extContext                         = 0x05
    
    func description() -> String {
      switch self {
      case .ifData:
        return "IfData"
      case .ifDataWithStream:
        return "IfDataWithStream"
      case .extData:
        return "ExtData"
      case .extDataWithStream:
        return "ExtDataWithStream"
      case .ifContext:
        return "IfContext"
      case .extContext:
        return "ExtContext"
      }
    }
  }
  public enum TsiType : UInt8 {             // Timestamp - Integer
    case none                               = 0x00
    case utc                                = 0x01
    case gps                                = 0x02
    case other                              = 0x03
    
    func description() -> String {
      switch self {
      case .none:
        return "None"
      case .utc:
        return "Utc"
      case .gps:
        return "Gps"
      case .other:
        return "Other"
      }
    }
  }
  public enum TsfType : UInt8 {             // Timestamp - Fractional
    case none                               = 0x00
    case sampleCount                        = 0x01
    case realtime                           = 0x02
    case freeRunning                        = 0x03
    
    func description() -> String {
      switch self {
      case .none:
        return "None"
      case .sampleCount:
        return "SampleCount"
      case .realtime:
        return "Realtime"
      case .freeRunning:
        return "FreeRunning"
      }
    }
  }
  public enum PacketClassCode : UInt16 {    // Packet Class Codes
    case meter                              = 0x8002
    case panadapter                         = 0x8003
    case waterfall                          = 0x8004
    case opus                               = 0x8005
    case daxIq24                            = 0x02e3
    case daxIq48                            = 0x02e4
    case daxIq96                            = 0x02e5
    case daxIq192                           = 0x02e6
    case daxAudio                           = 0x03e3
    case discovery                          = 0xffff
    
    func description() -> String {
      switch self {
      case .meter:
        return "Meter"
      case .panadapter:
        return "Panadapter"
      case .waterfall:
        return "Waterfall"
      case .opus:
        return "Opus"
      case .daxIq24:
        return "DaxIq24"
      case .daxIq48:
        return "DaxIq48"
      case .daxIq96:
        return "DaxIq96"
      case .daxIq192:
        return "DaxIq192"
      case .daxAudio:
        return "DaxAudio"
      case .discovery:
        return "Discovery"
      }
    }
  }
}
