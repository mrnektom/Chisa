package org.chisa.intellij

import com.intellij.psi.util.PsiTreeUtil
import com.intellij.testFramework.fixtures.BasePlatformTestCase
import org.chisa.intellij.psi.*

class ChisaImportResolveTest : BasePlatformTestCase() {

    override fun getTestDataPath(): String = "src/test/resources"

    fun testImportSymbolResolvesToDeclaration() {
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
            """.trimIndent()
        )

        val importStmt = PsiTreeUtil.findChildOfType(file, ChisaImportStatement::class.java)
        assertNotNull("IMPORT_STATEMENT should exist", importStmt)

        val symbols = importStmt!!.getImportSymbols()
        assertEquals("Should have one import symbol", 1, symbols.size)

        val symbol = symbols[0]
        assertEquals("get_ten", symbol.getOriginalName())
        assertNull(symbol.getAlias())
        assertEquals("get_ten", symbol.name)

        val resolved = symbol.reference.resolve()
        assertNotNull("Import symbol should resolve to declaration in lib.chisa", resolved)
        assertInstanceOf(resolved, ChisaFnDeclaration::class.java)
        assertEquals("get_ten", (resolved as ChisaFnDeclaration).name)
    }

    fun testAliasedImportResolvesCorrectly() {
        myFixture.addFileToProject(
            "lib.chisa",
            """
            fn add(a: number, b: number): number = a;
            """.trimIndent()
        )
        val file = myFixture.configureByText(
            "main.chisa",
            """
            import { add as sum } from "./lib.chisa";
            """.trimIndent()
        )

        val importStmt = PsiTreeUtil.findChildOfType(file, ChisaImportStatement::class.java)
        assertNotNull(importStmt)

        val symbols = importStmt!!.getImportSymbols()
        assertEquals(1, symbols.size)

        val symbol = symbols[0]
        assertEquals("add", symbol.getOriginalName())
        assertEquals("sum", symbol.getAlias())
        assertEquals("sum", symbol.name) // visible name is the alias

        val resolved = symbol.reference.resolve()
        assertNotNull("Aliased import should resolve to original declaration", resolved)
        assertInstanceOf(resolved, ChisaFnDeclaration::class.java)
        assertEquals("add", (resolved as ChisaFnDeclaration).name)
    }

    fun testImportPathResolvesToFile() {
        val libFile = myFixture.addFileToProject(
            "lib.chisa",
            """
            fn helper() = 0;
            """.trimIndent()
        )
        val file = myFixture.configureByText(
            "main.chisa",
            """
            import { helper } from "./lib.chisa";
            """.trimIndent()
        )

        val importStmt = PsiTreeUtil.findChildOfType(file, ChisaImportStatement::class.java)
        assertNotNull(importStmt)

        val importPath = importStmt!!.getImportPath()
        assertNotNull("IMPORT_PATH should exist", importPath)
        assertEquals("./lib.chisa", importPath!!.getPathString())

        val resolved = importPath.reference.resolve()
        assertNotNull("Import path should resolve to file", resolved)
        assertEquals(libFile, resolved)
    }

    fun testImportedSymbolUsedInCodeResolvesThrough() {
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

        // Find the reference expression for get_ten in `let x = get_ten()`
        val refs = PsiTreeUtil.findChildrenOfType(file, ChisaReferenceExpression::class.java)
        val getTenRef = refs.find { it.text == "get_ten" }
        assertNotNull("Should find reference to get_ten in code", getTenRef)

        val resolved = getTenRef!!.reference.resolve()
        // The reference should resolve directly to the fn declaration in the external file (one-hop)
        assertNotNull("Reference to imported symbol should resolve", resolved)
        assertInstanceOf(resolved, ChisaFnDeclaration::class.java)
        assertEquals("get_ten", (resolved as ChisaFnDeclaration).name)
    }

    fun testExportFromResolvesTransitively() {
        myFixture.addFileToProject(
            "original.chisa",
            """
            fn foo(): number = 42;
            """.trimIndent()
        )
        myFixture.addFileToProject(
            "reexporter.chisa",
            """
            export { foo } from "./original.chisa";
            """.trimIndent()
        )
        val file = myFixture.configureByText(
            "main.chisa",
            """
            import { foo } from "./reexporter.chisa";
            """.trimIndent()
        )

        val importStmt = PsiTreeUtil.findChildOfType(file, ChisaImportStatement::class.java)
        assertNotNull(importStmt)

        val symbol = importStmt!!.getImportSymbols().first()
        val resolved = symbol.reference.resolve()
        assertNotNull("Import through export-from should resolve transitively", resolved)
        assertInstanceOf(resolved, ChisaFnDeclaration::class.java)
        assertEquals("foo", (resolved as ChisaFnDeclaration).name)
    }

    fun testUseStatementParses() {
        val file = myFixture.configureByText(
            "main.chisa",
            """
            enum Color { }
            use Color.{ Red, Green, Blue };
            """.trimIndent()
        )

        val useStmt = PsiTreeUtil.findChildOfType(file, ChisaUseStatement::class.java)
        assertNotNull("USE_STATEMENT should exist", useStmt)
        assertEquals("Color", useStmt!!.getEnumName())

        val variants = useStmt.getVariantSymbols()
        assertEquals(3, variants.size)
        assertEquals("Red", variants[0].getOriginalName())
        assertEquals("Green", variants[1].getOriginalName())
        assertEquals("Blue", variants[2].getOriginalName())
    }

    fun testExportFromMakesSymbolLocallyVisible() {
        myFixture.addFileToProject(
            "original.chisa",
            """
            fn foo(): number = 42;
            """.trimIndent()
        )
        val file = myFixture.configureByText(
            "main.chisa",
            """
            export { foo } from "./original.chisa";
            let x = foo();
            """.trimIndent()
        )

        val refs = PsiTreeUtil.findChildrenOfType(file, ChisaReferenceExpression::class.java)
        val fooRef = refs.find { it.text == "foo" }
        assertNotNull("Should find reference to foo in code", fooRef)

        val resolved = fooRef!!.reference.resolve()
        assertNotNull("export-from should make symbol locally visible", resolved)
        assertInstanceOf(resolved, ChisaFnDeclaration::class.java)
        assertEquals("foo", (resolved as ChisaFnDeclaration).name)
    }

    fun testUseStatementResolvesToEnumVariant() {
        val file = myFixture.configureByText(
            "main.chisa",
            """
            enum Color { Red, Green, Blue }
            use Color.{ Red };
            """.trimIndent()
        )

        val useStmt = PsiTreeUtil.findChildOfType(file, ChisaUseStatement::class.java)
        assertNotNull("USE_STATEMENT should exist", useStmt)

        val symbols = useStmt!!.getVariantSymbols()
        assertEquals(1, symbols.size)

        val resolved = symbols[0].reference.resolve()
        assertNotNull("Use symbol should resolve to enum variant", resolved)
        assertInstanceOf(resolved, ChisaEnumVariant::class.java)
        assertEquals("Red", (resolved as ChisaEnumVariant).name)
    }

    fun testUseStatementVariantUsedInCodeResolvesToEnumVariant() {
        val file = myFixture.configureByText(
            "main.chisa",
            """
            enum Color { Red, Green, Blue }
            use Color.{ Red };
            let x = Red;
            """.trimIndent()
        )

        val refs = PsiTreeUtil.findChildrenOfType(file, ChisaReferenceExpression::class.java)
        val redRef = refs.find { it.text == "Red" }
        assertNotNull("Should find reference to Red in code", redRef)

        val resolved = redRef!!.reference.resolve()
        assertNotNull("Reference to used variant should resolve", resolved)
        assertInstanceOf(resolved, ChisaEnumVariant::class.java)
        assertEquals("Red", (resolved as ChisaEnumVariant).name)
    }

    fun testUseWithImportedEnumResolvesVariant() {
        myFixture.addFileToProject(
            "colors.chisa",
            """
            enum Color { Red, Green, Blue }
            """.trimIndent()
        )
        val file = myFixture.configureByText(
            "main.chisa",
            """
            import { Color } from "./colors.chisa";
            use Color.{ Red };
            let x = Red;
            """.trimIndent()
        )

        val refs = PsiTreeUtil.findChildrenOfType(file, ChisaReferenceExpression::class.java)
        val redRef = refs.find { it.text == "Red" }
        assertNotNull("Should find reference to Red in code", redRef)

        val resolved = redRef!!.reference.resolve()
        assertNotNull("use with imported enum should resolve variant", resolved)
        assertInstanceOf(resolved, ChisaEnumVariant::class.java)
        assertEquals("Red", (resolved as ChisaEnumVariant).name)
    }

    fun testForLoopVariableResolvesInsideBody() {
        val file = myFixture.configureByText(
            "main.chisa",
            """
            fn test() {
                for (let i = 0; i < 10; i = i + 1) {
                    let x = i;
                }
            }
            """.trimIndent()
        )

        val refs = PsiTreeUtil.findChildrenOfType(file, ChisaReferenceExpression::class.java)
        // Find the reference to 'i' inside the for body (let x = i)
        val iRefs = refs.filter { it.text == "i" }
        assertTrue("Should find references to i", iRefs.isNotEmpty())

        // The last 'i' reference (in let x = i) should resolve to the var declaration
        val lastIRef = iRefs.last()
        val resolved = lastIRef.reference.resolve()
        assertNotNull("For-loop variable should resolve inside body", resolved)
        assertInstanceOf(resolved, ChisaVarDeclaration::class.java)
    }

    fun testIfConditionReferenceResolves() {
        val file = myFixture.configureByText(
            "main.chisa",
            """
            let flag = true;
            if (flag) {
                let x = 1;
            }
            """.trimIndent()
        )

        val refs = PsiTreeUtil.findChildrenOfType(file, ChisaReferenceExpression::class.java)
        val flagRef = refs.find { it.text == "flag" }
        assertNotNull("Should find reference to flag in if condition", flagRef)

        val resolved = flagRef!!.reference.resolve()
        assertNotNull("Reference in if condition should resolve", resolved)
        assertInstanceOf(resolved, ChisaVarDeclaration::class.java)
        assertEquals("flag", (resolved as ChisaVarDeclaration).name)
    }

    fun testWhileConditionReferenceResolves() {
        val file = myFixture.configureByText(
            "main.chisa",
            """
            let running = true;
            fn test() {
                while (running) {
                    let x = 1;
                }
            }
            """.trimIndent()
        )

        val refs = PsiTreeUtil.findChildrenOfType(file, ChisaReferenceExpression::class.java)
        val runningRef = refs.find { it.text == "running" }
        assertNotNull("Should find reference to running in while condition", runningRef)

        val resolved = runningRef!!.reference.resolve()
        assertNotNull("Reference in while condition should resolve", resolved)
        assertInstanceOf(resolved, ChisaVarDeclaration::class.java)
        assertEquals("running", (resolved as ChisaVarDeclaration).name)
    }

    fun testUnresolvedImportSymbolReturnsNull() {
        myFixture.addFileToProject(
            "lib.chisa",
            """
            fn something_else() = 0;
            """.trimIndent()
        )
        val file = myFixture.configureByText(
            "main.chisa",
            """
            import { nonexistent } from "./lib.chisa";
            """.trimIndent()
        )

        val importStmt = PsiTreeUtil.findChildOfType(file, ChisaImportStatement::class.java)
        assertNotNull(importStmt)

        val symbol = importStmt!!.getImportSymbols().first()
        val resolved = symbol.reference.resolve()
        assertNull("Reference to nonexistent symbol should not resolve", resolved)
    }
}
