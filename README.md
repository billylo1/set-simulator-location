# Trip Simulator

This is a simple trip simulation tool for on the iOS Simulator that comes with Xcode.  To use it, just specify the starting and ending location, the tool will generate a route for you and send location updates every 0.5 seconds.  It is similar to the standard iOS simulator's location simulation feature (except that you can now use your own route, as opposed to the Freeway Drive simulation.) Note that it sends location updates only (no speed, altitude or direction information)

<a href="http://www.youtube.com/watch?feature=player_embedded&v=oXz5YIWNWUE
" target="_blank"><img src="http://img.youtube.com/vi/oXz5YIWNWUE/0.jpg" 
alt="demo" width=100% border="10" /></a>


## Usage

Enter starting and ending location, press Generate route, choose a simulation speed (1x, 5x, 10x, 100x) and press Start Simulation

NOTE: If you have multiple booted simulators, the location will be set on all of them.

## Installation

Use pre-compiled binary:  Download it from the release folder and launch it directly.

Build it yourself:  Clone this repo, open Trip Simulator.xcodeproj in Xcode 

## Development

Xcode 11.6 was used to develop Trip Simulator.  The UI code uses the set-simulator-location project from lyft and MapKit on macOS.

## License

Apache 2.0 (same as set-simulator-location)
