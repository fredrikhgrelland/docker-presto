# docker-presto

Custom Presto docker image which includes:

- consul connect plugin (https://github.com/gugalnikov/presto-consul-connect)
- compiled airlift http-client library to disable hostname verification (https://github.com/airlift/airlift/pull/858)