DO NOT DEVIATE FROM THIS ARCHITECTURE. PUTTING RANDOM MODULES IN THE MODULES FOLDER IS CONSIDERED WRONG.

ReplicatedStorage - Storage for client and server stuff

ReplicatedStorage.Services - Services are interfaces/modules used to control a 
specific, major aspect of the game. As you can see, TagService already exists,
and it's used as a pipeline for automatically linking tagged instances to
modules (usually classes). 

ReplicatedStorage.Classes - Classes are any class in the form of Roblox's class
syntax. These might be used through Tagger, they might not. Please take note of
syntax. Please take note of how
connections should be handled. Any connections should be stored in self.Connections
which is created from a local function called setUpConnections.

ReplicatedStorage.Config - Configs are any predefined "settings" that relate
to a certain topic. Note ExampleConfig, which is named by the topic "Example" 
followed by "Config". It returns back only the table.

ReplicatedStorage.Communication - This is where any RemoteEvents or RemoteFunctions
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

--------------------------------------------------------------------------

WORKFLOW RULES

1. READ README.md FIRST

Read README.md at the root at the start of every session, every time, before
doing anything else. It is the index of every script in the repo. Do not begin
searching, planning, or editing until you have read it.

2. CHECK THE DOCS BEFORE CREATING ANYTHING

Before creating any new file or writing any new functionality, check README.md
and the Documentation folder to confirm it does not already exist. If something
close already exists, extend that implementation. Do not duplicate a service,
class, config, or helper that is already documented.

3. UPDATE THE DOCS AFTER EVERY CHANGE

After any change, update the matching file(s) under Documentation and the
matching line(s) in README.md. A change is not finished until the docs describe
it. Documentation mirrors the container layout:
Documentation/<Container>/<Folder>.md

4. GIT

Commit only the files you changed. The sequence is always: add only those
files, commit, `git pull --no-rebase -X ours`, then push to main. Never force
push. There are no branches - do not create one, do not switch to one.

Why `-X ours`: Roblox script sync writes every collaborator's edits onto this
disk automatically, so the working tree is always the latest version of the
game and must win any merge conflict - but collaborators still push their own
commits to GitHub for attribution, so their history has to be merged in rather
than overwritten.

5. NEVER WRITE CODE COMMENTS

Not one. No narration, no section headers, no docstrings, no TODOs.

6. NEVER ADD FILES TO ANY MODULES FOLDER

The Modules folders are legacy placement. New shared helpers become Services or
Classes.
