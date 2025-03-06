//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import CoreCommands
import PackageGraph
import PackageModel

import var TSCBasic.stdoutStream
import class TSCBasic.TerminalController

extension TerminalController {
    fileprivate func clearScreen() {
        write("\u{001b}[2J")
        write("\u{001b}[H")
        flush()
    }
}

/// A stack of "cards" to display one at a time at the command line.
struct CardStack {
    var terminal: TerminalController

    /// The representation of a stack of cards.
    var cards = [Card]()

    /// The tool used for eventually building and running a chosen snippet.
    var swiftCommandState: SwiftCommandState

    /// When true, the escape sequence for clearing the terminal should be
    /// printed first.
    private var needsToClearScreen = true

    init(package: ResolvedPackage, snippetGroups: [SnippetGroup], swiftCommandState: SwiftCommandState) {
        // this interaction is done on stdout
        self.terminal = TerminalController(stream: TSCBasic.stdoutStream)!
        self.cards = [TopCard(package: package, snippetGroups: snippetGroups, swiftCommandState: swiftCommandState)]
        self.swiftCommandState = swiftCommandState
    }

    mutating func push(_ card: Card) {
        self.cards.append(card)
    }

    mutating func pop() {
        self.cards.removeLast()
    }

    mutating func clear() {
        self.cards.removeAll()
    }

    func askForLineInput(prompt: String?) -> String? {
        let isColorized: Bool = self.swiftCommandState.options.logging.colorDiagnostics

        if let prompt {
            isColorized ?
                print(brightBlack { prompt }.terminalString()) :
                print(plain { prompt }.terminalString())
        }
        isColorized ?
            self.terminal.write(">>> ", inColor: .green, bold: true)
            : self.terminal.write(">>> ", inColor: .noColor, bold: false)

        return readLine(strippingNewline: true)
    }

    mutating func run() async {
        var inputFinished = false
        while !inputFinished {
            guard let top = cards.last else {
                break
            }

            if self.needsToClearScreen {
                self.terminal.clearScreen()
                self.needsToClearScreen = false
            }

            print(top.render())

            // Assume input finished until proven otherwise, i.e. when readLine returns
            // `nil`.
            inputFinished = true

            askForLine: while let line = askForLineInput(prompt: top.inputPrompt) {
                inputFinished = false
                let trimmedLine = String(
                    line.drop { $0.isWhitespace }
                        .reversed()
                        .drop { $0.isWhitespace }
                        .reversed()
                )
                let response = await top.acceptLineInput(trimmedLine)
                switch response {
                case .none:
                    continue askForLine
                case .push(let card):
                    self.push(card)
                    self.needsToClearScreen = true
                    break askForLine
                case .pop(let error):
                    self.cards.removeLast()
                    if let error {
                        self.swiftCommandState.observabilityScope.emit(error)
                        self.needsToClearScreen = false
                    } else {
                        self.needsToClearScreen = !self.cards.isEmpty
                    }
                    break askForLine
                case .quit:
                    return
                }
            }
        }
    }
}
