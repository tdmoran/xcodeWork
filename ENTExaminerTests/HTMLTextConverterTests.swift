import Foundation
import Testing
@testable import ENTExaminer

@Suite("HTMLTextConverter")
struct HTMLTextConverterTests {

    @Test("Strips simple HTML tags")
    func stripsSimpleTags() {
        let text = HTMLTextConverter.convert("<p>Hello <b>world</b></p>")
        #expect(text.contains("Hello"))
        #expect(text.contains("world"))
        #expect(!text.contains("<"))
    }

    @Test("Removes script blocks")
    func removesScripts() {
        let text = HTMLTextConverter.convert("<p>Before</p><script>alert('xss')</script><p>After</p>")
        #expect(!text.contains("alert"))
        #expect(text.contains("Before"))
        #expect(text.contains("After"))
    }

    @Test("Removes style blocks")
    func removesStyles() {
        let text = HTMLTextConverter.convert("<p>Content</p><style>body { color: red; }</style>")
        #expect(!text.contains("color"))
        #expect(text.contains("Content"))
    }

    @Test("Removes nav and footer")
    func removesNavAndFooter() {
        let text = HTMLTextConverter.convert("<nav>Navigation</nav><main>Main Content</main><footer>Footer</footer>")
        #expect(!text.contains("Navigation"))
        #expect(!text.contains("Footer"))
        #expect(text.contains("Main Content"))
    }

    @Test("Decodes named HTML entities")
    func decodesNamedEntities() {
        let text = HTMLTextConverter.decodeEntities("&amp; &lt; &gt; &quot; &#39;")
        #expect(text == "& < > \" '")
    }

    @Test("Decodes numeric entities")
    func decodesNumericEntities() {
        let text = HTMLTextConverter.decodeEntities("&#65; &#66; &#67;")
        #expect(text == "A B C")
    }

    @Test("Decodes hex entities")
    func decodesHexEntities() {
        let text = HTMLTextConverter.decodeEntities("&#x41; &#x42;")
        #expect(text == "A B")
    }

    @Test("Handles empty input")
    func handlesEmptyInput() {
        let text = HTMLTextConverter.convert("")
        #expect(text == "")
    }

    @Test("Collapses excessive whitespace")
    func collapsesWhitespace() {
        let text = HTMLTextConverter.convert("<p>Hello     world</p>")
        #expect(!text.contains("     "))
    }
}
