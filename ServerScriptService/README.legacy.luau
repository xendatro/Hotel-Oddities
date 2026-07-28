--[[


ReplicatedStorage - Storage for client and server stuff

ReplicatedStorage.Services - Services are interfaces/modules used to control a 
specific, major aspect of the game. As you can see, TagService already exists,
and it's used as a pipeline for automatically linking tagged instances to
modules (usually classes). 

ReplicatedStorage.Classes - Classes are any class in the form of Roblox's class
syntax. These might be used through Tagger, they might not. Please observe the 
ExampleClass file. Please take note of syntax. Please take note of how
connections should be handled. Any connections should be stored in self.Connections
which is created from a local function called setUpConnections.

ReplicatedStorage.Config - Configs are any predefined "settings" that relate
to a certain topic. Note ExampleConfig, which is named by the topic "Example" 
followed by "Config". It returns back only the table.

ReplicatedStoroage.Communication - This is where any RemoteEvents or RemoteFunctions
will be stored. This folder is organized by subfolders which describe what the topic
is about, which contain RemoteEvents or RemoteFunctions that are actions.

ServerStorage - Storage for server stuff specifically. If something should not be
revealed to the client at all, keep it here.

ServerStorage.Services - These are the same as ReplicatedStorage.Services, but
they are exclusively server.

ServerStorage.Classes - These are the same as ReplicatedStorage.Classes, but they
are exclusively server.

ServerStorage.Config - These are the same as ReplicatedStorage.Config, but they
are exclusively server.

ALL Services (unless specifically changed) are self initializing as a result of Tagger 
in modules from the Init in either StarterPlayerScripts (client) or ServerScriptService
(server). Therefore, there is no reason to ever make an :Init() method on any
service. It is fine to just put the connections at the bottom.


]]