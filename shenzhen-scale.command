#__BANG__/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

if [ "$#" -eq 0 ]; then
  echo "SHENZHEN I/O GUI Scale"
  echo
  echo "  1) 原版 1x"
  echo "  2) 1.5x"
  echo "  3) 2x"
  echo "  4) 2.5x"
  echo "  5) 3x"
  echo "  s) 查看当前状态"
  echo "  r) 恢复原配置"
  echo
  read -r -p "选择： " choice
  case "$choice" in
    1) set -- 1 ;;
    2) set -- 1.5 ;;
    3) set -- 2 ;;
    4) set -- 2.5 ;;
    5) set -- 3 ;;
    s|S) set -- status ;;
    r|R) set -- restore ;;
    *) echo "无效选择"; exit 1 ;;
  esac
fi

exec "$(dirname "$0")/shenzhen-scale" "$@"
