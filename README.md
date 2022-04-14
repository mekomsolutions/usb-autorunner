# usb-autorunner
Debian bash applications to automatically and securely run instructions passed via a USB drive on a Linux server.

### USB Autorunner dev
This app provides the set of tools that allows generating a secure pack that you can send via a USB drive. more in [Wiki](#wiki) on how to create a package.

### USB Autorunner
This app is responsible on decrypting the pack if it's available in the USB drive once detected, and then run the script in the pack.

### USB Autorunner profiles

Profiles are a set of predefined scripts to help generating a package for a specific purpose, the package provides a custom Mekom profiles.

## Wiki

### How to create a pack

A pack is an encrypted zip file that contains mainly an initial script named `run.sh` that will be executed once the pack is running.
To create a pack we first have to make sure to provide the certificates (check [here](#how-to-provide-certificates)).

To create a pack run

```
usb-autorunner generate -p <profile-name>
```

with `profile-name` is the name of the profile in the profiles folder `/opt/usb-autorunner/profiles`
By default usb-autorunner comes with two profiles: `sysinfo` and `troubleshoot` (more profiles are provided by the usb-autorunner-profiles package)


### How to provide certificates

Certificates are important for usb-autorunner to generate a secured pack. You can generate your own public and private certs using a tool like `openssl` and place them in `/etc/usb-autorunner/certificates` under the names `public.pem` and `private.pem` for the public cert and private cert respectively. Alternatively you can run

```
usb-autorunner config -c
```
to generate a default certificates for usb-autorunner

**Note**: The certificates should be the same in the machine that will later run the usb drive
