# xAPITester
## Tcp API Explorer for the FlexRadio (TM) 6000 series software defined radios.

Builds on macOS 10.13 using XCode 9.2 and Swift 4 with a Deployment
Target of macOS 10.10

==========================================================================

Comments to: douglas.adams@me.com

==========================================================================

This version supports SmartLink (TM).


Usage:

Please see the xAPITester.pdf file in this project or run the app and click
the HELP menu choice.

A compiled DEBUG build executable (with SwiftyUserDefaults.framework embedded in it)
is contained in the GitHub Release if you would rather not build from sources.

If you require a RELEASE build you will have to build from sources and will need:

SwiftyUserDefaults.framework ( available at https://github.com/radex/SwiftyUserDefaults )

==========================================================================

CocoaAsyncSocket is embedded in this project as source code
(version 7.6.1 as of 2017-06-24
see https://github.com/robbiehanson/CocoaAsyncSocket)

