//
//  Api.swift
//  CommonCode
//
//  Created by Douglas Adams on 12/27/17.
//  Copyright © 2018 Douglas Adams & Mario Illgen. All rights reserved.
//

// --------------------------------------------------------------------------------
// MARK: - Api delegate protocol
//
// --------------------------------------------------------------------------------

public protocol ApiDelegate {
  
  /// A message has been sent to the Radio (hardware)
  ///
  /// - Parameter text:           the text of the message
  ///
  func sentMessage(_ text: String)
  
  /// A message has been received from the Radio (hardware)
  ///
  /// - Parameter text:           the text of the message
  func receivedMessage(_ text: String)
  
  /// A command sent to the Radio (hardware) needs to register a Reply Handler
  ///
  /// - Parameters:
  ///   - sequenceId:             the sequence number of the Command
  ///   - replyTuple:             a Reply Tuple
  ///
  func addReplyHandler(_ sequenceId: SequenceId, replyTuple: ReplyTuple)
  
  /// The default Reply Handler (to process replies to Commands sent to the Radio hardware)
  ///
  /// - Parameters:
  ///   - command:                a Command string
  ///   - seqNum:                 the Command's sequence number
  ///   - responseValue:          the response contined in the Reply to the Command
  ///   - reply:                  the descriptive text contained in the Reply to the Command
  ///
  func defaultReplyHandler(_ command: String, seqNum: String, responseValue: String, reply: String)
  
  /// Process received UDP Vita packets
  ///
  /// - Parameter vitaPacket: a Vita packet
  ///
  func streamHandler(_ vitaPacket: Vita)
}

// --------------------------------------------------------------------------------
// MARK: - API Class implementation
//
//      manages the connections to the Radio (hardware), responsible for the
//      creation / destruction of the Radio class (the object analog of the
//      Radio hardware)
//
// --------------------------------------------------------------------------------

public final class Api                      : TcpManagerDelegate, UdpManagerDelegate {
  
  static let kId                            = "xLib6000"                    // API Name
  static let kDomainId                      = "net.k3tzr"                   // Domain name
  static let kBundleIdentifier              = Api.kDomainId + "." + Api.kId
  static let kTcpTimeout                    = 0.5                           // seconds

  // ----------------------------------------------------------------------------
  // MARK: - Public properties
  
  public var availableRadios                : [RadioParameters] {           // Radios discovered
    return _radioFactory.availableRadios }
  public let log                            = Log.sharedInstance
  public var delegate                       : ApiDelegate?                  // API delegate
  public var radio                          : Radio?                        // current Radio class
  public var activeRadio                    : RadioParameters?              // Radio params
  public var pingerEnabled                  = true                          // Pinger enable
  public var isWan                          = false                         // Remote connection
  public var wanConnectionHandle            = ""                            // Wan connection handle

  public private(set) var apiVersionMajor   = 0                             // numeric versions of Radio firmware version
  public private(set) var apiVersionMinor   = 0
  
  public let kApiFirmwareSupport            = "2.1.33.x"                    // The Radio Firmware version supported by this API
  
  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  private var _apiState                     : ApiState = .started           // state of the API
  private var _tcp                          : TcpManager!                   // TCP connection class (commands)
  private var _udp                          : UdpManager!                   // UDP connection class (streams)
  private var _primaryCmdTypes              = [Api.Command]()               // Primary command types to be sent
  private var _secondaryCmdTypes            = [Api.Command]()               // Secondary command types to be sent
  private var _subscriptionCmdTypes         = [Api.Command]()               // Subscription command types to be sent
  private var _primaryCommands              = [CommandTuple]()              // Primary commands to be sent
  private var _secondaryCommands            = [CommandTuple]()              // Secondary commands to be sent
  private var _subscriptionCommands         = [CommandTuple]()              // Subscription commands to be sent
  private let _clientIpSemaphore            = DispatchSemaphore(value: 0)   // semaphore to signal that we have got the client ip

  // GCD Concurrent Queue
  private let _objectQ                      = DispatchQueue(label: Api.kId + ".objectQ", attributes: [.concurrent])

  // GCD Serial Queues
  private let _tcpReceiveQ                  = DispatchQueue(label: Api.kId + ".tcpReceiveQ", qos: .userInitiated)
  private let _tcpSendQ                     = DispatchQueue(label: Api.kId + ".tcpSendQ")
  private let _udpReceiveQ                  = DispatchQueue(label: Api.kId + ".udpReceiveQ", qos: .userInitiated)
  private let _udpRegisterQ                 = DispatchQueue(label: Api.kId + ".udpRegisterQ", qos: .background)
  private let _pingQ                        = DispatchQueue(label: Api.kId + ".pingQ")
  private let _parseQ                       = DispatchQueue(label: Api.kId + ".parseQ", qos: .userInteractive)
  private let _workerQ                      = DispatchQueue(label: Api.kId + ".workerQ")

  private var _radioFactory                 = RadioFactory()                // Radio Factory class
  private var _pinger                       : Pinger?                       // Pinger class
  private var _clientName                   = ""
  private var _isGui                        = true                          // GUI enable
  private var _lowBW                        = false                         // low bandwidth connect

  private let kNoError                      = "0"

  // ----- Backing properties - SHOULD NOT BE ACCESSED DIRECTLY, USE PUBLICS IN THE EXTENSION -----
  //
  private var _connectionState              = ConnectionState.disconnected(reason: .normal)
  private var _localIP                      = "0.0.0.0"                     // client IP for radio
  private var _localUDPPort                 : UInt16 = 0                    // bound UDP port
  //
  // ----- Backing properties - SHOULD NOT BE ACCESSED DIRECTLY, USE PUBLICS IN THE EXTENSION -----

  // ----------------------------------------------------------------------------
  // MARK: - Singleton
  
  /// Provide access to the API singleton
  ///
  public static var sharedInstance = Api()
  
  private init() {
    // "private" prevents others from calling init()
    
    // initialize a Manager for the TCP Command stream
    _tcp = TcpManager(tcpReceiveQ: _tcpReceiveQ, tcpSendQ: _tcpSendQ, delegate: self, timeout: Api.kTcpTimeout)
    
    // initialize a Manager for the UDP Data Streams
    _udp = UdpManager(udpReceiveQ: _udpReceiveQ, udpRegisterQ: _udpRegisterQ, delegate: self)
    
    // update the State
    _apiState = .initialized
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Public methods
  
  /// Connect to a Radio
  ///
  /// - Parameters:
  ///     - selectedRadio:        a RadioParameters struct for the desired Radio
  ///     - primaryCmdTypes:      array of "primary" command types (defaults to .all)
  ///     - secondaryCmdTYpes:    array of "secondary" command types (defaults to .all)
  ///     - subscriptionCmdTypes: array of "subscription" commandtypes (defaults to .all)
  /// - Returns:                  Success / Failure
  ///
  public func connect(_ selectedRadio: RadioParameters, clientName: String, isGui: Bool = true,
                      primaryCmdTypes: [Api.Command] = [.allPrimary],
                      secondaryCmdTypes: [Api.Command] = [.allSecondary],
                      subscriptionCmdTypes: [Api.Command] = [.allSubscription]) -> Bool {
    
    _clientName = clientName
    _isGui = isGui

    // ignore if already connected
    if selectedRadio != activeRadio {
      
      switch _apiState {
        
      case .started:                          // can't connect while in the .started state
        break
        
      case .active:                           // active with a different radio
        
        // Disconnect the active Radio
        disconnect(reason: .normal)
        
        activeRadio = nil
        
        self.radio = nil
        
        // if enabled, resume listening for Discovery broadcasts
        _radioFactory.resume()
        
        fallthrough
        
      case .initialized:                      // not connected but initialized
        
        // Create a Radio class
        radio = Radio(api: self, objectQ: _objectQ)
        
        activeRadio = selectedRadio
        
        // save the Command types
        _primaryCmdTypes = primaryCmdTypes
        _secondaryCmdTypes = secondaryCmdTypes
        _subscriptionCmdTypes = subscriptionCmdTypes
        
        // start a connection to the Radio
        if _tcp.connect(radioParameters: selectedRadio, isWan: isWan) {
          
          // if enabled, pause listening for Discovery broadcasts
          _radioFactory.pause()
          
          // check the versions
          checkFirmware()
          
          // update the State
          _apiState = .active
          
        } else {
          activeRadio = nil
        }
      }
    }
    // returns sucess if active
    return (_apiState == ApiState.active)
  }
  /// Disconnect from the active Radio
  ///
  /// - Parameter reason:         a reason code
  ///
  public func disconnect(reason: DisconnectReason = .normal) {
    
    // if pinger active, stop pinging
    if _pinger != nil {
      _pinger = nil
      log.msg("Pinger stopped", level: .error, function: #function, file: #file, line: #line)
    }
    // the radio class will be removed, inform observers
    NC.post(.radioWillBeRemoved, object: activeRadio as Any?)
    
    // disconnect TCP
    _tcp.disconnect()
    
    // unbind and close udp
    _udp.unbind()
    
    activeRadio = nil
    radio = nil
    
    // update the State
    _apiState = .initialized
    
    // the radio class has been removed, inform observers
    NC.post(.radioHasBeenRemoved, object: nil)
  }
  /// Send a command to the Radio (hardware)
  ///
  /// - Parameters:
  ///   - command:        a Command String
  ///   - flag:           use "D"iagnostic form
  ///   - callback:       a callback function (if any)
  ///
  public func send(_ command: String, diagnostic flag: Bool = false, replyTo callback: ReplyHandler? = nil) {
    
    // tell the TcpManager to send the command (and optionally setup a callback)
    let seqNumber = _tcp.send(command, diagnostic: flag, replyTo: callback)

    // register to be notified when reply received
    delegate?.addReplyHandler( String(seqNumber), replyTuple: (replyTo: callback, command: command) )
  }
  /// Send a command to the Radio (hardware), first check that a Radio is connected
  ///
  /// - Parameters:
  ///   - command:        a Command String
  ///   - flag:           use "D"iagnostic form
  ///   - callback:       a callback function (if any)
  /// - Returns:          Success / Failure
  ///
  public func sendWithCheck(_ command: String, diagnostic flag: Bool = false, replyTo callback: ReplyHandler? = nil) -> Bool {
    
    // abort if no connection
    guard _tcp.isConnected else { return false }
    
    // send
    send(command, diagnostic: flag, replyTo: callback)

    return true
  }
  /// Send a Vita packet to the Radio
  ///
  /// - Parameters:
  ///   - data:       a Vita-49 packet as Data
  ///
  public func sendVitaData(_ data: Data?) {
    
    // if data present
    if let dataToSend = data {
      
      // send it (no validity checks are performed)
      _udp.sendData(dataToSend)
    }
  }
  /// Send the collection of commands to configure the connection
  ///
  public func sendCommands() {
    
    // setup commands
    _primaryCommands = setupCommands(_primaryCmdTypes)
    _subscriptionCommands = setupCommands(_subscriptionCmdTypes)
    _secondaryCommands = setupCommands(_secondaryCmdTypes)
    
    // send the initial commands
    sendCommandList(_primaryCommands)
    
    // send the subscription commands
    sendCommandList(_subscriptionCommands)
    
    // send the secondary commands
    sendCommandList(_secondaryCommands)
  }

  // ----------------------------------------------------------------------------
  // MARK: - Internal methods
  
  /// Called by the Tcp & Udp Manager delegates when a connection state change occurs
  ///
  /// - Parameters:
  ///   - state:  the new State
  ///
  internal func setConnectionState(_ state: ConnectionState) {
    
    connectionState = state
    
    // take appropriate action
    switch state {
      
    case .tcpConnected(let host, let port):
      
      // log it
      log.msg("TCP connected to \(isWan ? "REMOTE" : "LOCAL") Radio @ \(host), Port \(port)", level: .info, function: #function, file: #file, line: #line)

      // a tcp connection has been established, inform observers
      NC.post(.tcpDidConnect, object: nil)
      
      _tcp.readNext()
      
      if !isWan {
        // establish a UDP port for the Data Streams
        _udp.bind(radioParameters: activeRadio!, isWan: self.isWan)
      } else {
        
        let cmd = "wan validate handle=" + wanConnectionHandle // TODO: + "\n"
        send(cmd, replyTo: nil)
      }
      
    case .udpBound(let port):
      
      // UDP (streams) connection established, initialize the radio
      log.msg("UDP bound to Port \(port)", level: .info, function: #function, file: #file, line: #line)
      
      localUDPPort = port

      // a UDP port has been bound, inform observers
      NC.post(.udpDidBind, object: nil)
      
      // a UDP bind has been established
      _udp.beginReceiving()

      // if WAN connection reset the state to .clientConnected as the true connection state
      if isWan {
        
        connectionState = .clientConnected
      }

    case .clientConnected:
      
      // code to be executed after an IP Address has been obtained
      func connectionCompletion() {
        
        // send the initial commands
        sendCommands()
        
        // set the streaming UDP port
        if isWan {
          // Wan, establish a UDP port for the Data Streams
          _udp.bind(radioParameters: activeRadio!, isWan: true, clientHandle: wanConnectionHandle)
          
        } else {
          // Local
          send(Api.Command.clientUdpPort.rawValue + "\(localUDPPort)")
        }
        // start pinging
        if pingerEnabled {
          
          log.msg("Pinger started", level: .error, function: #function, file: #file, line: #line)
          _pinger = Pinger(tcpManager: _tcp, pingQ: _pingQ)
        }
        // TCP & UDP connections established, inform observers
        NC.post(.clientDidConnect, object: activeRadio as Any?)
      }
      
      log.msg("Client connection established", level: .info, function: #function, file: #file, line: #line)
      
      // could this be a remote connection?
      if apiVersionMajor >= 2 {
        
        // YES, when connecting to a WAN radio, the public IP address of the connected
        // client must be obtained from the radio.  This value is used to determine
        // if audio streams from the radio are meant for this client.
        // (IsAudioStreamStatusForThisClient() checks for LocalIP)
        send("client ip", replyTo: clientIpReplyHandler)
        
        // take this off the socket receive queue
        _workerQ.async { [unowned self] in
          
          // wait for the response
          let time = DispatchTime.now() + DispatchTimeInterval.milliseconds(5000)
          _ = self._clientIpSemaphore.wait(timeout: time)

          // complete the connection
          connectionCompletion()
        }
        
      } else {
        
        // NO, use the ip of the local interface
        localIP = _tcp.interfaceIpAddress

        // complete the connection
        connectionCompletion()
      }

    case .disconnected(let reason):
      
      // TCP connection disconnected
      log.msg("Disconnected, reason = \(reason)", level: .error, function: #function, file: #file, line: #line)
      
      // TCP connection was disconnected, inform observers
      NC.post(.tcpDidDisconnect, object: reason)
      
    case .update( _, _):
      
      // FIXME: need to handle Update State ???
      log.msg("Update in process", level: .info, function: #function, file: #file, line: #line)
    }
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Private methods
  
  /// Determine if the Radio (hardware) Firmware version is compatable with the API version
  ///
  /// - Parameters:
  ///   - selectedRadio:      a RadioParameters struct
  ///
  private func checkFirmware() {
    
    // separate the parts of each version
    let apiVersionParts = kApiFirmwareSupport.components(separatedBy: ".")
    let radioVersionParts = activeRadio!.firmwareVersion!.components(separatedBy: ".")
    
    // compare the versions
    if apiVersionParts[0] != radioVersionParts[0] || apiVersionParts[1] != radioVersionParts[1] || apiVersionParts[2] != radioVersionParts[2] {
      log.msg("Update needed, Radio version = \(activeRadio!.firmwareVersion!), API supports version = \(kApiFirmwareSupport)", level: .warning, function: #function, file: #file, line: #line)
    }
    // set integer numbers for major and minor for fast comparision
    apiVersionMajor = Int(apiVersionParts[0]) ?? 0
    apiVersionMinor = Int(apiVersionParts[1]) ?? 0
  }
  /// Send a command list to the Radio
  ///
  /// - Parameters:
  ///   - commands:       an array of CommandTuple
  ///
  private func sendCommandList(_ commands: [CommandTuple]) {
    
    // send the commands to the Radio (hardware)
    for cmd in commands {
      
      send(cmd.command, diagnostic: cmd.diagnostic, replyTo: cmd.replyHandler)
    }
  }
  ///
  ///     Note: commands will be in default order if one of the .all... values is passed
  ///             otherwise commands will be in the order found in the incoming array
  ///
  /// Populate a Commands array
  ///
  /// - Parameters:
  ///   - commands:       an array of Commands
  /// - Returns:          an array of CommandTuple
  ///
  private func setupCommands(_ commands: [Api.Command]) -> [(CommandTuple)] {
    var array = [(CommandTuple)]()
    
    // return immediately if none required
    if !commands.contains(.none) {
      
      // check for the "all..." cases
      var adjustedCommands = commands
      if commands.contains(.allPrimary) {                             // All Primary
        
        adjustedCommands = Api.Command.allPrimaryCommands()
        
      } else if commands.contains(.allSecondary) {                    // All Secondary
        
        adjustedCommands = Api.Command.allSecondaryCommands()
        
      } else if commands.contains(.allSubscription) {                 // All Subscription
        
        adjustedCommands = Api.Command.allSubscriptionCommands()
      }
      
      // add all the specified commands
      for command in adjustedCommands {
        
        switch command {
          
        case .clientProgram:
          array.append( (command.rawValue + _clientName, false, delegate?.defaultReplyHandler) )
          
        case .clientLowBW:
          if _lowBW { array.append( (command.rawValue, false, nil) ) }
          
        case .meterList:
          array.append( (command.rawValue, false, delegate?.defaultReplyHandler) )
          
        case .info:
          array.append( (command.rawValue, false, delegate?.defaultReplyHandler) )
          
        case .version:
          array.append( (command.rawValue, false, delegate?.defaultReplyHandler) )
          
        case .antList:
          array.append( (command.rawValue, false, delegate?.defaultReplyHandler) )
          
        case .micList:
          array.append( (command.rawValue, false, delegate?.defaultReplyHandler) )
          
        case .clientGui:
          if _isGui { array.append( (command.rawValue, false, nil) ) }
          
        case .none, .allPrimary, .allSecondary, .allSubscription:   // should never occur
          break
          
        default:
          array.append( (command.rawValue, false, nil) )
        }
      }
    }
    return array
  }
  /// Reply handler for the "client ip" command
  ///
  /// - Parameters:
  ///   - command:                a Command string
  ///   - seqNum:                 the Command's sequence number
  ///   - responseValue:          the response contained in the Reply to the Command
  ///   - reply:                  the descriptive text contained in the Reply to the Command
  ///
  private func clientIpReplyHandler(_ command: String, seqNum: String, responseValue: String, reply: String) {
    
    // was an error code returned?
    if responseValue == kNoError {
      
      // NO, the reply value is the IP address
      localIP = reply.isValidIP4() ? reply : "0.0.0.0"

    } else {

      // YES, use the ip of the local interface
      localIP = _tcp.interfaceIpAddress
    }
    // signal completion of the "client ip" command
    _clientIpSemaphore.signal()
  }

  // ----------------------------------------------------------------------------
  // MARK: - Notification methods
  
  /// Add Notifications
  ///
  private func addNotifications() {
    
    // Pinging Started
    NC.makeObserver(self, with: #selector(tcpPingStarted(_:)), of: .tcpPingStarted, object: nil)
    
    // Ping Timeout
    NC.makeObserver(self, with: #selector(tcpPingTimeout(_:)), of: .tcpPingTimeout, object: nil)
  }
  /// Process .tcpPingStarted Notification
  ///
  /// - Parameters:
  ///   - note:       a Notification instance
  ///
  @objc private func tcpPingStarted(_ note: Notification) {
    
    log.msg("Pinging started", level: .verbose, function: #function, file: #file, line: #line)
  }
  /// Process .tcpPingTimeout Notification
  ///
  /// - Parameters:
  ///   - note:       a Notification instance
  ///
  @objc private func tcpPingTimeout(_ note: Notification) {
    
    log.msg("Ping timeout", level: .error, function: #function, file: #file, line: #line)
    
    // FIXME: Disconnect?
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - TcpManagerDelegate methods
  //    executes on the tcpReceiveQ

  /// Process a received message
  ///
  /// - Parameter msg:        text of the message
  ///
  func receivedMessage(_ msg: String) {
    
    // is it a non-empty message?
    if msg.count > 1 {
      
      // YES, pass it to the parser
      _parseQ.async { [ unowned self ] in
        self.delegate?.receivedMessage( String(msg.dropLast()) )
      }
    }
  }
  /// Process a sent message
  ///
  /// - Parameter text:         text of the message
  ///
  func sentMessage(_ text: String) {
    
    delegate?.sentMessage( String(text.dropLast()) )
  }
  /// Receive an Error message from TCP Manager
  ///
  /// - Parameter message:      the error message
  ///
  func tcpError(_ message: String) {
    
    log.msg("TCP error:  \(message)", level: .error, function: #function, file: #file, line: #line)
  }
  /// Respond to a TCP Connection/Disconnection event
  ///
  /// - Parameters:
  ///   - connected:  state of connection
  ///   - host:       host address
  ///   - port:       port number
  ///   - error:      error message
  ///
  func tcpState(connected: Bool, host: String, port: UInt16, error: String) {
    
    // connected?
    if connected {
      
      // YES, set state
      setConnectionState(.tcpConnected(host: host, port: port))
      
    } else {
      
      // NO, error?
      if error == "" {
        
        // NO, normal disconnect
        setConnectionState(.disconnected(reason: .normal))
        
      } else {
        
        // YES, disconnect with error (don't keep the UDP port open as it won't be reused with a new connection)
        _udp.unbind()
        setConnectionState(.disconnected(reason: .error(errorMessage: error)))
      }
    }
  }
  func addReplyHandler(_ sequenceId: SequenceId, replyTuple: ReplyTuple) {
    // not used
  }

  // ----------------------------------------------------------------------------
  // MARK: - UdpManager delegate methods
  //    executes on the udpReceiveQ
  
  /// Receive an Error message from UDP Manager
  ///
  /// - Parameters:
  ///   - message:    error message
  ///
  func udpError(_ message: String) {
    
    // UDP port encountered an error
    log.msg("UDP error:  \(message)", level: .error, function: #function, file: #file, line: #line)
  }
  /// Respond to a UDP Connection/Disconnection event
  ///
  /// - Parameters:
  ///   - bound:  state of binding
  ///   - port:   a port number
  ///   - error:  error message
  ///
  func udpState(bound : Bool, port: UInt16, error: String) {
    
    // bound?
    if bound {
      
      // YES, set state
      setConnectionState(.udpBound(port: port))
    }
    
    // TODO: should there be a udpUnbound state ?
    
  }
  /// Receive a State Change message from UDP Manager
  ///
  /// - Parameters:
  ///   - active:     the state
  ///
  func udpStreamStatus(active: Bool) {

    // UDP port active / timed out
    log.msg("\(active)", level: .verbose, function: #function, file: #file, line: #line)
  }
  /// Receive a UDP Stream packet
  ///
  /// - Parameter vita: a Vita packet
  ///
  func udpStreamHandler(_ vitaPacket: Vita) {
    
    delegate?.streamHandler(vitaPacket)
  }
}

// --------------------------------------------------------------------------------
// MARK: - Api Class extensions
//              - Public properties, no message to Radio
//              - Api enums
// --------------------------------------------------------------------------------

extension Api {
  
  // ----------------------------------------------------------------------------
  // MARK: - Public properties - KVO compliant (no message to Radio)
  
  public var connectionState: ConnectionState {
    get { return _objectQ.sync { _connectionState } }
    set { _objectQ.sync(flags: .barrier) { _connectionState = newValue } } }
  
  public var localIP: String {
    get { return _objectQ.sync { _localIP } }
    set { _objectQ.sync(flags: .barrier) { _localIP = newValue } } }
  
  public var localUDPPort: UInt16 {
    get { return _objectQ.sync { _localUDPPort } }
    set { _objectQ.sync(flags: .barrier) { _localUDPPort = newValue } } }

  // ----------------------------------------------------------------------------
  // MARK: - Api enums
  
  ///
  ///     Note: The "clientUdpPort" command must be sent AFTER the actual Udp port number has been determined.
  ///           The default port number may already be in use by another application.
  ///
  public enum Command: String {
    
    // GROUP A: none of this group should be included in one of the command sets
    case none
    case clientUdpPort                      = "client udpport "
    case allPrimary
    case allSecondary
    case allSubscription
    case clientIp                           = "client ip"
    
    // GROUP B: members of this group can be included in the command sets
    case antList                            = "ant list"
    case clientProgram                      = "client program "
    case clientGui                          = "client gui"
    case clientLowBW                        = "client low_bw_connect"
    case eqRx                               = "eq rxsc info"
    case eqTx                               = "eq txsc info"
    case info
    case meterList                          = "meter list"
    case micList                            = "mic list"
    case profileGlobal                      = "profile global info"
    case profileTx                          = "profile tx info"
    case profileMic                         = "profile mic info"
    case subAmplifier                       = "sub amplifier all"
    case subAudioStream                     = "sub audio_stream all"
    case subAtu                             = "sub atu all"
    case subCwx                             = "sub cwx all"
    case subDax                             = "sub dax all"
    case subDaxIq                           = "sub daxiq all"
    case subFoundation                      = "sub foundation all"
    case subGps                             = "sub gps all"
    case subMemories                        = "sub memories all"
    case subMeter                           = "sub meter all"
    case subPan                             = "sub pan all"
    case subRadio                           = "sub radio all"
    case subScu                             = "sub scu all"
    case subSlice                           = "sub slice all"
    case subTnf                             = "sub tnf all"
    case subTx                              = "sub tx all"
    case subUsbCable                        = "sub usb_cable all"
    case subXvtr                            = "sub xvtr all"
    case version
    
    // Note: Do not include GROUP A values in these return vales
    
    static func allPrimaryCommands() -> [Command] {
      return [.clientProgram, .clientLowBW, .clientGui]
    }
    static func allSecondaryCommands() -> [Command] {
      return [.info, .version, .antList, .micList, .profileGlobal,
              .profileTx, .profileMic, .eqRx, .eqTx]
    }
    static func allSubscriptionCommands() -> [Command] {
      return [.subRadio, .subTx, .subAtu, .subMeter, .subPan, .subSlice, .subTnf, .subGps,
              .subAudioStream, .subCwx, .subXvtr, .subMemories, .subDaxIq, .subDax,
              .subUsbCable, .subAmplifier, .subFoundation, .subScu]
    }
  }
  
  public enum DisconnectReason: Equatable {
    public static func ==(lhs: Api.DisconnectReason, rhs: Api.DisconnectReason) -> Bool {
      
      switch (lhs, rhs) {
      case (.normal, .normal): return true
      case let (.error(l), .error(r)): return l == r
      default: return false
      }
    }
    case normal
    case error (errorMessage: String)
  }
  
  public enum ApiState: Equatable {
    public static func ==(lhs: Api.ApiState, rhs: Api.ApiState) -> Bool {
      
      switch (lhs, rhs) {
      case (.started, .started): return true
      case (.initialized, .initialized): return true
      case (.active, .active): return true
      default: return false
      }
    }
    case started
    case initialized
    case active
  }
  
  public enum ConnectionState: Equatable {
    case clientConnected
    case disconnected(reason: DisconnectReason)
    case tcpConnected(host: String, port: UInt16)
    case udpBound(port: UInt16)
    case update(host: String, port: UInt16)
    
    public static func ==(lhs: ConnectionState, rhs: ConnectionState) -> Bool {
      switch (lhs, rhs) {
      case (.clientConnected, .clientConnected): return true
      case let (.disconnected(l), .disconnected(r)): return l == r
      case let (.tcpConnected(l), .tcpConnected(r)): return l.host == r.host && l.port == r.port
      case let (.udpBound(l), .udpBound(r)): return l == r
      case let (.update(l), .update(r)): return l.host == r.host && l.port == r.port
      default: return false
      }
    }
  }
  
  // --------------------------------------------------------------------------------
  // MARK: - Type Alias (alphabetical)
  
  public typealias CommandTuple = (command: String, diagnostic: Bool, replyHandler: ReplyHandler?)
  
}
