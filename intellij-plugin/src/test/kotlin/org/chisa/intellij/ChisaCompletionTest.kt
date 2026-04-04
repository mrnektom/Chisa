package org.chisa.intellij

import com.intellij.psi.util.PsiTreeUtil
import com.intellij.testFramework.fixtures.BasePlatformTestCase
import org.chisa.intellij.psi.ChisaImportPath

class ChisaCompletionTest : BasePlatformTestCase() {

    override fun getTestDataPath(): String = "src/test/resources"

    fun testCompletionIncludesLocalVariable() {
        myFixture.configureByText(
            "main.chisa",
            """
            let foo = 1;
            let x = f<caret>
            """.trimIndent()
        )
        val lookups = myFixture.completeBasic()
        assertNotNull("Completion should return results", lookups)
        val names = lookups.map { it.lookupString }
        assertTrue("Should contain 'foo', got: $names", names.contains("foo"))
    }

    fun testCompletionIncludesFunction() {
        myFixture.configureByText(
            "main.chisa",
            """
            fn bar() = 0;
            let x = b<caret>
            """.trimIndent()
        )
        val lookups = myFixture.completeBasic()
        assertNotNull("Completion should return results", lookups)
        val names = lookups.map { it.lookupString }
        assertTrue("Should contain 'bar', got: $names", names.contains("bar"))
    }

    fun testCompletionIncludesImportedSymbol() {
        myFixture.addFileToProject(
            "lib.chisa",
            """
            fn get_ten(): number = 10;
            """.trimIndent()
        )
        myFixture.configureByText(
            "main.chisa",
            """
            import { get_ten } from "./lib.chisa";
            let x = <caret>
            """.trimIndent()
        )
        val lookups = myFixture.completeBasic()
        assertNotNull("Completion should return results", lookups)
        val names = lookups.map { it.lookupString }
        assertTrue("Should contain 'get_ten', got: $names", names.contains("get_ten"))
    }

    fun testCompletionIncludesKeywords() {
        myFixture.configureByText(
            "main.chisa",
            """
            l<caret>
            """.trimIndent()
        )
        val lookups = myFixture.completeBasic()
        assertNotNull("Completion should return results", lookups)
        val names = lookups.map { it.lookupString }
        assertTrue("Should contain 'let', got: $names", names.contains("let"))
    }

    fun testCompletionAfterDotShowsEnumVariants() {
        myFixture.configureByText(
            "main.chisa",
            """
            enum Color { Red, Green }
            let x = Color.<caret>
            """.trimIndent()
        )
        val lookups = myFixture.completeBasic()
        assertNotNull("Completion should return results", lookups)
        val names = lookups.map { it.lookupString }
        assertTrue("Should contain 'Red', got: $names", names.contains("Red"))
        assertTrue("Should contain 'Green', got: $names", names.contains("Green"))
    }

    fun testCompletionAfterDotShowsStructFields() {
        myFixture.configureByText(
            "main.chisa",
            """
            struct Point { x: number, y: number }
            let p: Point;
            let v = p.<caret>
            """.trimIndent()
        )
        val lookups = myFixture.completeBasic()
        assertNotNull("Completion should return results", lookups)
        val names = lookups.map { it.lookupString }
        assertTrue("Should contain 'x', got: $names", names.contains("x"))
        assertTrue("Should contain 'y', got: $names", names.contains("y"))
    }

    fun testCompletionInTypePositionShowsTypes() {
        myFixture.configureByText(
            "main.chisa",
            """
            struct Point { x: number, y: number }
            let x: P<caret>
            """.trimIndent()
        )
        val lookups = myFixture.completeBasic()
        assertNotNull("Completion should return results", lookups)
        val names = lookups.map { it.lookupString }
        assertTrue("Should contain 'Point', got: $names", names.contains("Point"))
    }

    fun testCompletionInUseShowsEnumVariants() {
        myFixture.configureByText(
            "main.chisa",
            """
            enum Option { Some, None }
            use Option.{ <caret> }
            """.trimIndent()
        )
        val lookups = myFixture.completeBasic()
        assertNotNull("Completion should return results", lookups)
        val names = lookups.map { it.lookupString }
        assertTrue("Should contain 'Some', got: $names", names.contains("Some"))
        assertTrue("Should contain 'None', got: $names", names.contains("None"))
    }

    fun testImportPathReferenceVariantsIncludeFiles() {
        myFixture.addFileToProject("lib.chisa", "fn helper() = 0;")
        val file = myFixture.configureByText(
            "main.chisa",
            """
            import { x } from "./lib.chisa";
            """.trimIndent()
        )
        val importPath = PsiTreeUtil.findChildOfType(file, ChisaImportPath::class.java)
        assertNotNull("IMPORT_PATH should exist", importPath)
        val variants = importPath!!.reference.variants
        val names = variants.map { it.toString() }
        assertTrue("Should contain './lib.chisa', got: $names", names.contains("./lib.chisa"))
    }

    fun testCompletionAfterDotOnImportedStructType() {
        myFixture.addFileToProject(
            "types.chisa",
            """
            struct Point { x: number, y: number }
            """.trimIndent()
        )
        myFixture.configureByText(
            "main.chisa",
            """
            import { Point } from "./types.chisa";
            let p: Point;
            let v = p.<caret>
            """.trimIndent()
        )
        val lookups = myFixture.completeBasic()
        assertNotNull("Completion should return results", lookups)
        val names = lookups.map { it.lookupString }
        assertTrue("Should contain 'x', got: $names", names.contains("x"))
        assertTrue("Should contain 'y', got: $names", names.contains("y"))
    }

    fun testCompletionUsedVariantInExpression() {
        myFixture.configureByText(
            "main.chisa",
            """
            enum Color { Red }
            use Color.{ Red };
            let x = R<caret>
            """.trimIndent()
        )
        val lookups = myFixture.completeBasic()
        assertNotNull("Completion should return results", lookups)
        val names = lookups.map { it.lookupString }
        assertTrue("Should contain 'Red', got: $names", names.contains("Red"))
    }
}
