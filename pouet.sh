#!/usr/bin/env bash
source src/sh/littlesecrets.sh
ls_store_init
# ls_user_register "$USER" ~/.ssh/id_rsa

ls_secret_add sample.secret "Hello, World!"
ls_secret_key sample.secret

# ls_secret_get sample.secret
