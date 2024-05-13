getlast() {
    fc -ln "$1" "$1" | sed '1s/^[[:space:]]*//'
}
