# ssl-cert-check
Check SSL Expiration via bash


# Example multiple domains
Create a file called domains.txt and input all the domains you wanted to check
```
google.com
microsoft.com
bing.com
facebook.com
```

After that execute the following command
-----------------------------------------
```
for i in $(cat domains.txt); do ./ssl-cert-check.sh -s $i -x 10 -n; done
```


To Check only 1 domain ssl expiration
-------------------------------------
```
./ssl-cert-check.sh -s goadminops.com -x 10 -n
```


