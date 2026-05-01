package main

import (
	"fmt"
	"github.com/sagernet/sing-box/option"
)

func main() {
	var opts option.Options
	err := opts.UnmarshalJSON([]byte("{}"))
	fmt.Println("UnmarshalJSON err:", err)
}
