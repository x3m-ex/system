#!/bin/bash

if [ "$1" ] ; then
  num="$1"
else
  num=1
fi

BANKING_API_PORT=400$num \
iex --dot-iex ../.iex.exs --sname banking_api_$num -S mix
