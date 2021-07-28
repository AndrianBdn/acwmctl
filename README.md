# acwmctl 

A basic command-line tool to control Intesis Wi-Fi MH-AC-WIFI-1 ( AirConWithMe app alternative )

## Usage 

The command line tool only supports few commands that I personally need now: 

```sh
$ acwmctl on  # turn air conditioner on 
$ acwmctl fan 3 # set fan level to 3 (supported fan levels 1-4)
$ acwmctl off # turn air conditioner off 
```

## Building 

Type `make install` to build binary and copy it to ~/bin/ directory.


## Configuration 

create a file ~/.acwm
```json 
{
    "airconIPAddress" : "192.168.1.123",
    "username"        : "admin",
    "password"        : "admin"
}
```
