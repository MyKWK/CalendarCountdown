import Foundation

public struct MissionSymbol: Equatable, Identifiable, Sendable {
    public var systemName: String
    public var title: String

    public var id: String { systemName }

    public init(systemName: String, title: String) {
        self.systemName = systemName
        self.title = title
    }
}

public struct MissionSymbolGroup: Equatable, Identifiable, Sendable {
    public var title: String
    public var symbols: [MissionSymbol]

    public var id: String { title }

    public init(title: String, symbols: [MissionSymbol]) {
        self.title = title
        self.symbols = symbols
    }
}

/// Curated SF Symbols for missions. Names are Apple's standard symbol identifiers;
/// the glyphs ship with the OS, so no image assets need to be imported.
public enum MissionSymbolCatalog {
    public static let defaultSystemName = "flag.fill"

    public static let groups: [MissionSymbolGroup] = [
        MissionSymbolGroup(title: "目标", symbols: [
            .init(systemName: "flag.fill", title: "旗帜"),
            .init(systemName: "flag.checkered", title: "终点"),
            .init(systemName: "target", title: "靶心"),
            .init(systemName: "scope", title: "瞄准"),
            .init(systemName: "checkmark.seal.fill", title: "达成"),
            .init(systemName: "trophy.fill", title: "奖杯"),
            .init(systemName: "medal.fill", title: "奖牌"),
            .init(systemName: "chart.line.uptrend.xyaxis", title: "上升"),
            .init(systemName: "list.star", title: "清单"),
            .init(systemName: "calendar", title: "日历")
        ]),
        MissionSymbolGroup(title: "工作", symbols: [
            .init(systemName: "wrench.fill", title: "扳手"),
            .init(systemName: "hammer.fill", title: "锤子"),
            .init(systemName: "screwdriver.fill", title: "螺丝批"),
            .init(systemName: "briefcase.fill", title: "公文包"),
            .init(systemName: "building.2.fill", title: "公司"),
            .init(systemName: "desktopcomputer", title: "电脑"),
            .init(systemName: "laptopcomputer", title: "笔记本"),
            .init(systemName: "keyboard.fill", title: "键盘"),
            .init(systemName: "terminal.fill", title: "终端"),
            .init(systemName: "cpu", title: "芯片"),
            .init(systemName: "externaldrive.fill", title: "硬盘"),
            .init(systemName: "shippingbox.fill", title: "包装"),
            .init(systemName: "printer.fill", title: "打印")
        ]),
        MissionSymbolGroup(title: "学习", symbols: [
            .init(systemName: "book.fill", title: "书"),
            .init(systemName: "text.book.closed.fill", title: "课本"),
            .init(systemName: "graduationcap.fill", title: "毕业帽"),
            .init(systemName: "pencil", title: "铅笔"),
            .init(systemName: "lightbulb.fill", title: "灵感"),
            .init(systemName: "brain.head.profile", title: "思考"),
            .init(systemName: "doc.text.fill", title: "文档"),
            .init(systemName: "quote.opening", title: "写作")
        ]),
        MissionSymbolGroup(title: "生活", symbols: [
            .init(systemName: "heart.fill", title: "心"),
            .init(systemName: "figure.run", title: "跑步"),
            .init(systemName: "leaf.fill", title: "叶子"),
            .init(systemName: "cross.case.fill", title: "医疗"),
            .init(systemName: "bed.double.fill", title: "睡眠"),
            .init(systemName: "fork.knife", title: "餐饮"),
            .init(systemName: "cup.and.saucer.fill", title: "咖啡"),
            .init(systemName: "house.fill", title: "家"),
            .init(systemName: "cart.fill", title: "购物"),
            .init(systemName: "tshirt.fill", title: "衣物")
        ]),
        MissionSymbolGroup(title: "创造", symbols: [
            .init(systemName: "paintbrush.fill", title: "画笔"),
            .init(systemName: "camera.fill", title: "相机"),
            .init(systemName: "music.note", title: "音乐"),
            .init(systemName: "film.fill", title: "电影"),
            .init(systemName: "gamecontroller.fill", title: "游戏"),
            .init(systemName: "theatermasks.fill", title: "戏剧"),
            .init(systemName: "sportscourt.fill", title: "运动")
        ]),
        MissionSymbolGroup(title: "财务", symbols: [
            .init(systemName: "yensign.circle.fill", title: "人民币"),
            .init(systemName: "creditcard.fill", title: "卡片"),
            .init(systemName: "chart.bar.fill", title: "柱状图"),
            .init(systemName: "banknote.fill", title: "钞票"),
            .init(systemName: "percent", title: "百分比")
        ]),
        MissionSymbolGroup(title: "人际", symbols: [
            .init(systemName: "person.2.fill", title: "团队"),
            .init(systemName: "phone.fill", title: "电话"),
            .init(systemName: "envelope.fill", title: "邮件"),
            .init(systemName: "bubble.left.and.bubble.right.fill", title: "对话"),
            .init(systemName: "megaphone.fill", title: "公告")
        ]),
        MissionSymbolGroup(title: "出行", symbols: [
            .init(systemName: "airplane", title: "飞机"),
            .init(systemName: "car.fill", title: "汽车"),
            .init(systemName: "map.fill", title: "地图"),
            .init(systemName: "suitcase.fill", title: "行李箱"),
            .init(systemName: "tram.fill", title: "轨道"),
            .init(systemName: "bicycle", title: "自行车")
        ]),
        MissionSymbolGroup(title: "其他", symbols: [
            .init(systemName: "star.fill", title: "星星"),
            .init(systemName: "bolt.fill", title: "闪电"),
            .init(systemName: "flame.fill", title: "火焰"),
            .init(systemName: "moon.fill", title: "月亮"),
            .init(systemName: "sparkles", title: "闪光"),
            .init(systemName: "shield.fill", title: "盾牌"),
            .init(systemName: "lock.fill", title: "锁"),
            .init(systemName: "key.fill", title: "钥匙"),
            .init(systemName: "globe", title: "地球"),
            .init(systemName: "antenna.radiowaves.left.and.right", title: "信号")
        ])
    ]

    public static var all: [MissionSymbol] {
        groups.flatMap(\.symbols)
    }

    public static func resolved(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultSystemName : trimmed
    }

    public static func title(for systemName: String) -> String {
        let resolved = resolved(systemName)
        return all.first(where: { $0.systemName == resolved })?.title ?? resolved
    }

    public static func groups(matching query: String) -> [MissionSymbolGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return groups }
        return groups.compactMap { group in
            let symbols = group.symbols.filter {
                $0.title.localizedCaseInsensitiveContains(needle)
                    || $0.systemName.localizedCaseInsensitiveContains(needle)
            }
            return symbols.isEmpty ? nil : MissionSymbolGroup(title: group.title, symbols: symbols)
        }
    }
}
