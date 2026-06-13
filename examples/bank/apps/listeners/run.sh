#!/bin/bash

if [ "$1" ] ; then
  num="$1"
else
  num=1
fi

iex --dot-iex ../.iex.exs --sname banking_listeners_$num -S mix
