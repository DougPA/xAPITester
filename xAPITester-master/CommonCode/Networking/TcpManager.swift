//
//  TcpManager.swift
//  CommonCode
//
//  Created by Douglas Adams on 8/15/15.
//  Copyright © 2018 Douglas Adams & Mario Illgen. All rights reserved.
//

public typealias ReplyHandler = (_ command: String, _ seqNum: String, _ responseValue: String, _ reply: String) -> Void
public typealias SequenceId = String
public typealias ReplyTuple = (replyTo: ReplyHandler?, command: String)

import Foundation

// --------------------------------------------------------------------------------
// MARK: - TcpManager delegate protocol
//
// --------------------------------------------------------------------------------

protocol TcpManagerDelegate: class {
  
  func addReplyHandler(_ sequenceId: SequenceId, replyTuple: ReplyTuple)
  func receivedMessage(_ text: String)
  func sentMessage(_ text: String)
  func tcpError(_ message: String)
  func tcpState(connected: Bool, host: String, port: UInt16, error: String)
}

// ------------------------------------------------------------------------------
// MARK: - TcpManager Class implementation
//
//      manages all TCP communication between the API and the Radio (hardware)
//
// ------------------------------------------------------------------------------

final class TcpManager                      : NSObject, GCDAsyncSocketDelegate {

  public private(set) var interfaceIpAddress = "0.0.0.0"

  // ----------------------------------------------------------------------------
  // MARK: - Internal properties
  
  internal var isConnected                  : Bool { return _tcpSocket.isConnected }
  
  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  private weak var _delegate                : TcpManagerDelegate?           // class to receive TCP data

  private var _tcpReceiveQ                  : DispatchQueue                 // serial GCD Queue for receiving Radio Commands
  private var _tcpSendQ                     : DispatchQueue                 // serial GCD Queue for sending Radio Commands
  private var _tcpSocket                    : GCDAsyncSocket!               // GCDAsync TCP socket object
  private var _seqNum                       = 0                             // Sequence number
  private var _timeout                      = 0.0                           // timeout in seconds
  private var _isWan                        = false                         // is a TLS connection needed

  // ----------------------------------------------------------------------------
  // MARK: - Initialization
  
  /// Initialize a TcpManager
  ///
  /// - Parameters:
  ///   - tcpReceiveQ:    a serial Queue for Tcp receive activity
  ///   - tcpSendQ:       a serial Queue for Tcp send activity
  ///   - delegate:       a delegate fro Tcp activity
  ///   - timeout:        connection timeout (seconds)
  ///
  init(tcpReceiveQ: DispatchQueue, tcpSendQ: DispatchQueue, delegate: TcpManagerDelegate, timeout: Double = 0.5) {
    
    _tcpReceiveQ = tcpReceiveQ
    _tcpSendQ = tcpSendQ
    _delegate = delegate
    _timeout = timeout
    
    super.init()
    
    // get a socket & set it's parameters
    _tcpSocket = GCDAsyncSocket(delegate: self, delegateQueue: _tcpReceiveQ)
    _tcpSocket.isIPv4PreferredOverIPv6 = true
    _tcpSocket.isIPv6Enabled = false
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Public methods
  
  /// Attempt to connect to the Radio (hardware)
  ///
  /// - Parameters:
  ///   - radioParameters:        a RadioParameters instance
  ///   - isWan:                  enable WAN connection
  /// - Returns:                  success / failure
  ///
  func connect(radioParameters: RadioParameters, isWan: Bool = false) -> Bool {
    
    _isWan = isWan
    var port = 0
    var interface: String?
    
    var success = true
    
    _seqNum = 0
    
    if (_isWan) {
      if (radioParameters.requiresHolePunch) {
        // If we require hole punching then the radio port and the source port
        // will both be the same
        if radioParameters.localInterfaceIP == "0.0.0.0" {
          // not initialized
          return false
        }
        port = radioParameters.negotiatedHolePunchPort
        interface = radioParameters.localInterfaceIP + ":" + String(port)
      } else {
        port = radioParameters.publicTlsPort
        //Connected = _commandCommunication.Connect(_ip, PublicTlsPort);
      }
    } else {
      
      port = radioParameters.port
    }
    
    do {
      // attempt to connect to the Radio (with timeout)
      if let ifa = interface {
        try _tcpSocket.connect(toHost: radioParameters.ipAddress, onPort: UInt16(port), viaInterface: ifa, withTimeout: _timeout)
      } else {
        try _tcpSocket.connect(toHost: radioParameters.ipAddress, onPort: UInt16(port), withTimeout: _timeout)
      }
      
    } catch _ {
      
      success = false
    }
    return success
  }
  /// Disconnect from the Radio (hardware)
  ///
  func disconnect() {
    
    // tell the socket to close
    _tcpSocket.disconnect()
  }
  /// Send a Command to the Radio (hardware), optionally register to be Notified upon receipt of a Reply
  ///
  /// - Parameters:
  ///   - cmd:            a Command string
  ///   - diagnostic:     whether to add "D" suffix
  ///   - replyTo:        ReplyHandler (if any)
  /// - Returns:          the Sequence Number of the Command
  ///
  func send(_ cmd: String, diagnostic: Bool = false, replyTo callback: ReplyHandler? = nil) -> Int {
    var lastSeqNum = 0
    var command = ""
    
    _tcpSendQ.sync {
      
      // assemble the command
      command =  "C" + "\(diagnostic ? "D" : "")" + "\(self._seqNum)|" + cmd + "\n"
      
      // register to be notified when reply received
      _delegate?.addReplyHandler( String(self._seqNum), replyTuple: (replyTo: callback, command: cmd) )
      
      // send it, no timeout, tag = segNum
      self._tcpSocket.write(command.data(using: String.Encoding.utf8, allowLossyConversion: false)!, withTimeout: -1, tag: self._seqNum)
      
      lastSeqNum = _seqNum
      
      // increment the Sequence Number
      _seqNum += 1
    }
    self._delegate?.sentMessage(command)
    
    // return the Sequence Number of the last command
    return lastSeqNum
  }
  /// Read the next data block (with an indefinite timeout)
  ///
  func readNext() {
    
    _tcpSocket.readData(to: GCDAsyncSocket.lfData(), withTimeout: -1, tag: 0)
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - GCDAsyncSocket Delegate methods
  //            executes on the tcpReceiveQ
  
  /// Called when the TCP/IP connection has been disconnected
  ///
  /// - Parameters:
  ///   - sock:       the disconnected socket
  ///   - err:        the error
  ///
  @objc func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
    
    // set the state
    _delegate?.tcpState(connected: false, host: sock.connectedHost ?? "", port: sock.connectedPort, error: (err == nil) ? "" : err!.localizedDescription)
  }
  /// Called after the TCP/IP connection has been established
  ///
  /// - Parameters:
  ///   - sock:       the socket
  ///   - host:       the host
  ///   - port:       the port
  ///
  @objc func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
    
    // Connected
    interfaceIpAddress = sock.localHost!
    
    // is this a Wan connection?
    if _isWan {
      
      // YES, start radio TLS connection
      var tlsSettings = [String : NSObject]()
      tlsSettings[GCDAsyncSocketManuallyEvaluateTrust as String] = 1 as NSObject

      sock.startTLS(tlsSettings)

    } else {
      
      // NO, set the state
      _delegate?.tcpState(connected: true, host: sock.connectedHost ?? "", port: sock.connectedPort, error: "")
    }
  }
  /// Called when data has been read from the TCP/IP connection
  ///
  /// - Parameters:
  ///   - sock:       the socket data was received on
  ///   - data:       the Data
  ///   - tag:        the Tag associated with this receipt
  ///
  @objc func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
    
    // get the bytes that were read
    let text = String(data: data, encoding: .ascii)!
    
    // pass them to our delegate
    _delegate?.receivedMessage(text)
    
    // trigger the next read
    readNext()
  }
  /**
   * Called after the socket has successfully completed SSL/TLS negotiation.
   * This method is not called unless you use the provided startTLS method.
   *
   * If a SSL/TLS negotiation fails (invalid certificate, etc) then the socket will immediately close,
   * and the socketDidDisconnect:withError: delegate method will be called with the specific SSL error code.
   **/
  /// Called when a socket has been sceured
  ///
  /// - Parameter sock:       the socket that was secured
  ///
  @objc public func socketDidSecure(_ sock: GCDAsyncSocket) {
    
    // should not happen but...
    guard _isWan else { return }

    // set the state
    _delegate?.tcpState(connected: true, host: sock.connectedHost ?? "", port: sock.connectedPort, error: "")
  }
  /**
   * Allows a socket delegate to hook into the TLS handshake and manually validate the peer it's connecting to.
   *
   * This is only called if startTLS is invoked with options that include:
   * - GCDAsyncSocketManuallyEvaluateTrust == YES
   *
   * Typically the delegate will use SecTrustEvaluate (and related functions) to properly validate the peer.
   *
   * Note from Apple's documentation:
   *   Because [SecTrustEvaluate] might look on the network for certificates in the certificate chain,
   *   [it] might block while attempting network access. You should never call it from your main thread;
   *   call it only from within a function running on a dispatch queue or on a separate thread.
   *
   * Thus this method uses a completionHandler block rather than a normal return value.
   * The completionHandler block is thread-safe, and may be invoked from a background queue/thread.
   * It is safe to invoke the completionHandler block even if the socket has been closed.
   **/
  @objc public func socket(_ sock: GCDAsyncSocket, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
    
    // should not happen but...
    guard _isWan else { completionHandler(false) ; return }
    
    // there are no validations for the radio connection
    completionHandler(true)
  }
}
