package org.chisa.intellij

import com.intellij.psi.util.PsiTreeUtil
import com.intellij.testFramework.fixtures.BasePlatformTestCase
import org.chisa.intellij.highlighting.ChisaSyntaxHighlighter
import org.chisa.intellij.psi.*

class ChisaAnnotatorTest : BasePlatformTestCase() {

    fun testFunctionDeclarationHighlighted() {
        val file = myFixture.configureByText(
            "main.chisa",
            """
            fn greet() {}
            """.trimIndent()
        )
        myFixture.doHighlighting()
        val highlights = myFixture.doHighlighting().filter {
            it.forcedTextAttributesKey == ChisaSyntaxHighlighter.FUNCTION_NAME
        }
        assertFalse("Function declaration name should be highlighted", highlights.isEmpty())
        assertTrue(highlights.any { file.text.substring(it.startOffset, it.endOffset) == "greet" })
    }

    fun testFunctionCallHighlighted() {
        val file = myFixture.configureByText(
            "main.chisa",
            """
            fn greet() {}
            greet();
            """.trimIndent()
        )
        myFixture.doHighlighting()
        val highlights = myFixture.doHighlighting().filter {
            it.forcedTextAttributesKey == ChisaSyntaxHighlighter.FUNCTION_CALL
        }
        assertFalse("Function call should be highlighted", highlights.isEmpty())
        assertTrue(highlights.any { file.text.substring(it.startOffset, it.endOffset) == "greet" })
    }

    fun testFunctionCallInsideBlockHighlighted() {
        val file = myFixture.configureByText(
            "main.chisa",
            """
            fn greet() {}
            fn main() {
                greet();
            }
            """.trimIndent()
        )
        myFixture.doHighlighting()
        val highlights = myFixture.doHighlighting().filter {
            it.forcedTextAttributesKey == ChisaSyntaxHighlighter.FUNCTION_CALL
        }
        assertFalse("Function call inside block should be highlighted", highlights.isEmpty())
    }

    fun testImportedFunctionCallHighlighted() {
        myFixture.addFileToProject(
            "lib.chisa",
            """
            fn get_ten(): number = 10;
            """.trimIndent()
        )
        val file = myFixture.configureByText(
            "main.chisa",
            """
            import { get_ten } from "./lib.chisa";
            let x = get_ten();
            """.trimIndent()
        )
        myFixture.doHighlighting()
        val highlights = myFixture.doHighlighting().filter {
            it.forcedTextAttributesKey == ChisaSyntaxHighlighter.FUNCTION_CALL
        }
        assertFalse("Imported function call should be highlighted", highlights.isEmpty())
        assertTrue(highlights.any { file.text.substring(it.startOffset, it.endOffset) == "get_ten" })
    }

    fun testStructFieldHighlighted() {
        val file = myFixture.configureByText(
            "main.chisa",
            """
            struct Point {
                x: number,
                y: number
            }
            """.trimIndent()
        )
        myFixture.doHighlighting()
        val highlights = myFixture.doHighlighting().filter {
            it.forcedTextAttributesKey == ChisaSyntaxHighlighter.FIELD_NAME
        }
        assertFalse("Struct field declarations should be highlighted", highlights.isEmpty())
        val highlightedTexts = highlights.map { file.text.substring(it.startOffset, it.endOffset) }
        assertTrue("x field should be highlighted", highlightedTexts.contains("x"))
        assertTrue("y field should be highlighted", highlightedTexts.contains("y"))
    }

    fun testReferenceToVariableNotHighlightedAsFunctionCall() {
        myFixture.configureByText(
            "main.chisa",
            """
            let x = 10;
            let y = x;
            """.trimIndent()
        )
        myFixture.doHighlighting()
        val highlights = myFixture.doHighlighting().filter {
            it.forcedTextAttributesKey == ChisaSyntaxHighlighter.FUNCTION_CALL
        }
        assertTrue("Variable reference should NOT be highlighted as function call", highlights.isEmpty())
    }

    fun testStructLiteralFieldsHighlighted() {
        val file = myFixture.configureByText(
            "main.chisa",
            """
            struct Point {
                x: number,
                y: number
            }
            let p = Point { x: 3, y: 4 };
            """.trimIndent()
        )
        myFixture.doHighlighting()
        val highlights = myFixture.doHighlighting().filter {
            it.forcedTextAttributesKey == ChisaSyntaxHighlighter.FIELD_NAME
        }
        val highlightedTexts = highlights.map { file.text.substring(it.startOffset, it.endOffset) }
        // Should include both declaration fields and literal fields
        assertEquals("Should highlight x twice (decl + literal) and y twice (decl + literal)",
            4, highlightedTexts.count { it == "x" || it == "y" })
    }

    fun testStructLiteralFieldResolvesToDeclaration() {
        val file = myFixture.configureByText(
            "main.chisa",
            """
            struct Point {
                x: number,
                y: number
            }
            let p = Point { x: 3, y: 4 };
            """.trimIndent()
        )

        val refs = PsiTreeUtil.findChildrenOfType(file, ChisaReferenceExpression::class.java)
        // Find the 'x' reference inside the struct literal (not the struct declaration field)
        val xRefs = refs.filter { it.text == "x" }
        assertTrue("Should find reference to x", xRefs.isNotEmpty())

        // The struct literal field 'x' should resolve to the struct field declaration
        val literalXRef = xRefs.find { ref ->
            ref.reference.resolve() is ChisaStructField
        }
        assertNotNull("Struct literal field x should resolve to ChisaStructField", literalXRef)
        val resolved = literalXRef!!.reference.resolve() as ChisaStructField
        assertEquals("x", resolved.name)
    }
}
