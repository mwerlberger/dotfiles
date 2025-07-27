# boot logs

- list all boot options:
```
journalctl --list-boots
```

- print log from last boot from the given id/offset:
```
journalctl -b -1
```