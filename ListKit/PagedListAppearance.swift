//
//  PagedListAppearance.swift
//  ListKit
//
//  列表文案与占位视图的定制入口。
//
//  背景：组件原本把占位态与 footer 文案写死（中文），接入到需要本地化的 App 时会顶掉
//  App 自己的空态/失败态样式。这里把「文案」与「占位视图」都抽出来，默认值与原来完全一致，
//  因此对既有调用方零影响；App 只需传入自己的本地化文案与视图即可。
//
//  用法：
//  ```swift
//  let appearance = PagedListAppearance(
//      loadingText: "Loading…",
//      retryText: "Retry",
//      exhaustedText: "No more",
//      emptyView: AnyView(PLEmptyView(title: "No Result", message: "…")),
//      failedView: { message in AnyView(MyFailedView(message)) }
//  )
//  LazyWaterfallListView(model: model, appearance: appearance, …)
//  ```
//

import SwiftUI

/// 分页列表的文案与占位视图定制。
///
/// * 文案类字段直接替换 footer / 占位态里的文字；
/// * 视图类字段为 `nil` 时沿用组件内置实现（`ProgressView` / `ContentUnavailableView`）。
public struct PagedListAppearance {

    // MARK: 文案

    /// footer 加载中
    public var loadingText: String
    /// footer 失败重试按钮
    public var retryText: String
    /// footer 到底提示（列表为空时不显示）
    public var exhaustedText: String
    /// 首屏失败占位标题
    public var failedTitle: String
    /// 首屏空数据占位标题
    public var emptyTitle: String

    // MARK: 占位视图（给了就用，没给用内置）

    /// 首屏加载占位
    public var loadingView: AnyView?
    /// 空数据占位
    public var emptyView: AnyView?
    /// 失败占位（入参为错误描述）
    public var failedView: ((String) -> AnyView)?

    public init(
        loadingText: String = "加载中…",
        retryText: String = "重试",
        exhaustedText: String = "没有更多了",
        failedTitle: String = "加载失败",
        emptyTitle: String = "暂无内容",
        loadingView: AnyView? = nil,
        emptyView: AnyView? = nil,
        failedView: ((String) -> AnyView)? = nil
    ) {
        self.loadingText = loadingText
        self.retryText = retryText
        self.exhaustedText = exhaustedText
        self.failedTitle = failedTitle
        self.emptyTitle = emptyTitle
        self.loadingView = loadingView
        self.emptyView = emptyView
        self.failedView = failedView
    }

    /// 默认外观：与组件原有表现完全一致
    public static let `default` = PagedListAppearance()
}
