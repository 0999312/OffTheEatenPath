class_name StateRestoredEvent
extends Event
## 存档已恢复完毕，所有界面都应该重新拉一次快照。
##
## 为什么需要它：主场景里 HUD 比 GameBridge 先 ready，HUD 进树时拉到的还是
## GameState 初始值；恢复存档不会逐项发 CoinChanged / CatalogDiscovered，
## 所以读档后必须有一次「整体重拉」的信号。读档只发生在启动时一次，无需携带数据。
