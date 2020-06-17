# FIRST THINGS FIRST

git clone
open in sublime
CTRL + SHIFT + F
find github.com/Zonama/
Replace github.com/TrigsC/
in bootstrap.sh change theanswer to TrigsC
Save all files

# BaseBox

Tools to build and publish a new basebox for the ZonamaDev environment

## Building the "Base Box" from scratch

Download and install Git, VirtualBox and Vagrant

## Windows Host

### Downloads
* Github's Git for Windows: https://git-for-windows.github.io/
* VirtualBox for Windows: https://www.vagrantup.com/downloads.html
* Vagrant for Windows: https://www.vagrantup.com/downloads.html
 
Launch Git Bash: Start -> Programs -> Git Bash
or
Right click in desired directory -> Bit Bash

#### Build the box

```bash
git clone https://github.com/Zonama/ZonamaDev.git
cd ZonamaDev/basebox
./build.sh
```

Currently this takes about 10 mins on a fairly fast internet connection and nice sized box.

Follow steps in next section to prepare the box.

### Manual steps

1. Resize the virtualbox to 1280x800 using the Virtualbox view menu.
2. Launch eclipse, set default workspace as ~/workspace
3. Install the Lua Development Tools LDT (http://download.eclipse.org/ldt/releases/milestones/)
4. Import Projects in ~/workspace/Core3
5. Associate *.idl *.lua *.h *.cpp *.lst in Eclipse: Window -> Preferences -> General -> Editors -> File Associations 
6. Launch Chrome and verify it's positioned properly then close it.
7. Launch Firefox and verify it's positioned properly, set home page to http://www.swgemu.com/
8. Launch Atom, open ~/workspace/Core3 as a folder, navigate to config.lua and leave open
9. Clean up the box for packaging: exec sudo ~vagrant/ZonamaDev/basebox/scripts/package-prep.sh "0.0.X" (next box version number)
10. When the box halts from your host run: vagrant package
11. Close all windows

### Publish
1. Upload package-x.y.z.box to atlas
2. Set the new version to x.y.z
3. Don't forget to release the version in the atlas UI!
3. Test the new box:
```
cd ../fasttrack
vagrant destroy
sed -i 's/config.vm.box_version = ".*"/config.vm.box_version = "x.y.z"/' Vagrantfile
./setup.sh
```
If the tests pass then push the new fasttrack/Vagrantfile:
```
git add Vagrantfile
git commit -m "Bump to box version x.y.z"
git push
```
